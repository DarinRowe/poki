import SwiftUI
import UIKit

/// What Poki knows of its keyboard: iOS lists it as added, and it has answered. Poki cannot read
/// Full Access itself (#162): the keyboard answers the first time it comes up with it, so an added
/// keyboard that has not answered only needs to be shown once.
struct PokiKeyboardState {
    var added = PokiKeyboardTyping.added
    var answered = PokiKeyboardTyping.lastStatus != nil
    var lastDecline = UserDefaults.standard.string(forKey: PokiKeyboardTyping.lastDeclineKey)
    /// iOS says which keyboards are added (an empty list rules nothing out).
    var listed = !PokiKeyboardTyping.keyboards.isEmpty

    var ready: Bool { answered && (added || !listed) }
    var waitingForPanel: Bool { added && !answered }
    var word: LocalizedStringKey {
        if ready { return "Ready" }
        if waitingForPanel { return "One More Step" }
        return "Not Added"
    }
}

/// Setup's row for the keyboard: a tick, or what is missing.
struct PokiKeyboardSetupRow: View {
    @State private var state = PokiKeyboardState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        LabeledContent {
            if state.ready {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel(Text("Done"))
            } else {
                Text(state.word).foregroundStyle(.orange)
            }
        } label: {
            Label("Add the Poki Keyboard", systemImage: "keyboard")
        }
        .onAppear { state = PokiKeyboardState() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { state = PokiKeyboardState() } }
    }
}

/// Setup › Add the Poki Keyboard: what it is for, how to add it, and whether it has answered.
struct PokiKeyboardPage: View {
    @State private var state = PokiKeyboardState()
    @State private var wasAway = false
    @State private var trial = ""
    @FocusState private var trying: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section {
                // The same top row as Setup's other steps: the step's icon and name, then Done or what is missing.
                LabeledContent {
                    Text(state.ready ? "Done" : state.word).foregroundStyle(state.ready ? Color.green : Color.orange)
                } label: {
                    Label("Add the Poki Keyboard", systemImage: "keyboard")
                }
                if let last = state.lastDecline {
                    LabeledContent("Not Used Last Time") { Text(verbatim: last).foregroundStyle(.secondary) }
                }
            } footer: {
                Text("Poki types through its own keyboard panel, at a person’s pace. The panel has no keys. It shows while Poki types, and Take Over stops it.")
            }
            // Added, but the panel has not come up: a field here, so it can be shown without leaving Poki.
            if state.waitingForPanel {
                Section {
                    TextField("Tap here, then switch keyboards", text: $trial).focused($trying)
                } footer: {
                    Text("Tap the globe key below the keyboard and switch to Poki once. Poki only needs to see its panel appear, no typing. If the panel asks for Full Access, turn it on in Settings.")
                }
            }
            // The same list as Setup's other steps (Turn On Developer Mode). Once the keyboard is added these
            // steps are behind the person, so only the field above is left.
            if !state.waitingForPanel {
                HowToSection(lines: [
                    "Tap **Open Settings** below.",
                    "On Poki’s page, tap **Keyboards**.",
                    "Turn on **Poki**, then **Allow Full Access**.",
                ]) {
                    Text("If Poki’s page has no Keyboards row, open **Settings › General › Keyboard › Keyboards › Add New Keyboard**, choose **Poki**, then tap it in that list and turn on **Allow Full Access**.")
                }
            }
            Section {
                Button("Open Settings", systemImage: "gear") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            } footer: {
                Text("Keep your usual keyboards. Poki switches to its keyboard when it types and back to yours when it is done. Full Access lets the panel talk to Poki on this iPhone. It has no network access and never uses the clipboard.")
            }
        }
        .navigationTitle("Poki Keyboard")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            state = PokiKeyboardState()
            trying = state.waitingForPanel
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { wasAway = true }
            guard phase == .active else { return }
            state = PokiKeyboardState()
            // Back from Settings with the keyboard just added.
            if wasAway && state.waitingForPanel { trying = true }
            wasAway = false
        }
        // The panel writes its status the moment it comes up; nothing tells Poki, so look while waiting.
        .task(id: state.waitingForPanel && scenePhase == .active) {
            guard state.waitingForPanel, scenePhase == .active else { return }
            while (try? await Task.sleep(for: .milliseconds(500))) != nil {
                let now = PokiKeyboardState()
                guard !now.waitingForPanel else { continue }
                trying = false
                state = now
                return
            }
        }
    }
}

/// Setup › Advanced › Typing: how text is entered, and the keyboard's switches.
struct TypingSettingsSection: View {
    @AppStorage(NativeServicesWDA.typingMethodKey) private var method = "keyboard"
    @AppStorage(PokiKeyboardTyping.autoSwitchKey) private var autoSwitch = true
    @AppStorage(PokiKeyboardTyping.switchBackKey) private var switchBack = true
    @AppStorage(NativeServicesWDA.systemPinyinKey) private var systemPinyin = false
    @AppStorage("poki.experimental.userRoutines") private var userRoutines = false
    @State private var showLearning = false

    var body: some View {
        Section {
            Picker("Text Entry", selection: $method) {
                Text("Poki Keyboard").tag("keyboard")
                Text("Paste").tag("paste")
            }
            if method != "paste" {
                Toggle("Switch to It Automatically", isOn: $autoSwitch)
                Toggle("Switch Back When Finished", isOn: $switchBack)
                Toggle("System Pinyin Keyboard for Chinese", isOn: $systemPinyin)
            }
            if showLearning {
                Toggle("Create routines from user demonstrations", isOn: $userRoutines)
            }
        } header: {
            Text("Typing")
                .onLongPressGesture(minimumDuration: 3) { showLearning.toggle() }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if method == "paste" {
                    Text("Poki types with key presses and pastes what the keys can’t type, such as Chinese and emoji. Your clipboard is put back afterwards. The Poki keyboard is not used.")
                } else {
                    Text("Poki types through its own keyboard and never touches the clipboard. When the keyboard can’t be used, plain text is typed with key presses, and other text is not entered.")
                    if systemPinyin { Text("The system Pinyin keyboard is slower and reads the screen while it types.") }
                }
                if showLearning {
                    Text("Experimental. Observed corrections become user-assisted checkpoints, never guessed taps or unattended replay. Off by default.")
                }
            }
        }
    }
}
