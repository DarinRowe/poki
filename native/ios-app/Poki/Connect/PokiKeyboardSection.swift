import SwiftUI
import UIKit

/// Settings → Poki keyboard: whether the typing panel is set up, and how Poki uses it.
struct PokiKeyboardSection: View {
    @AppStorage(PokiKeyboardTyping.autoSwitchKey) private var autoSwitch = true
    @AppStorage(PokiKeyboardTyping.switchBackKey) private var switchBack = true
    @AppStorage(NativeServicesWDA.systemPinyinKey) private var systemPinyin = false
    @AppStorage("poki.experimental.userRoutines") private var userRoutines = false
    @State private var showLearning = false
    @State private var added = PokiKeyboardTyping.added
    @State private var answered = PokiKeyboardTyping.lastStatus != nil
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Section {
            LabeledContent("Keyboard") {
                Text(state).foregroundStyle(ready ? Color.secondary : Color.orange)
            }
            if !ready {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            Toggle("Switch to it automatically", isOn: $autoSwitch)
            Toggle("Switch back when finished", isOn: $switchBack)
            Toggle("Type Chinese with the system Pinyin keyboard", isOn: $systemPinyin)
            if showLearning {
                Toggle("Create routines from user demonstrations", isOn: $userRoutines)
            }
        } header: {
            Text("Poki keyboard")
                .onLongPressGesture(minimumDuration: 3) { showLearning.toggle() }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Poki types through its own keyboard panel, at a person’s pace. The panel has no keys: it shows while Poki types, and Take Over stops it. To set it up, add Poki under Settings → General → Keyboard → Keyboards, then allow Full Access. Keep your usual keyboards.")
                Text("Full Access lets the panel talk to Poki on this iPhone. It has no network access and never uses the clipboard. Without the panel, Poki types with key presses as before.")
                if systemPinyin {
                    Text("The system Pinyin keyboard is slower and reads the screen while it types.")
                }
                if showLearning {
                    Text("Experimental. Observed corrections become user-assisted checkpoints, never guessed taps or unattended replay. Off by default.")
                }
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    private var ready: Bool { answered && (added || PokiKeyboardTyping.keyboards.isEmpty) }

    private var state: LocalizedStringKey {
        if ready { return "Ready" }
        if added || answered { return "Needs Full Access" }
        return "Not added"
    }

    private func refresh() {
        added = PokiKeyboardTyping.added
        answered = PokiKeyboardTyping.lastStatus != nil
    }
}
