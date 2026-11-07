import SwiftUI

@main
struct PokiApp: App {
    @State private var model = AppModel()

    init() {
        // PokiLauncher (Rust) and the relay write to sockets the other side may have closed. In an app,
        // unlike a Rust executable, nothing ignores SIGPIPE, and it would end the whole app.
        signal(SIGPIPE, SIG_IGN)
    }

    var body: some Scene {
        WindowGroup {
            RootView().environment(model)
        }
    }
}

/// Home, with Settings as a sheet behind the gear, Voice as a sheet behind the waveform beside it, and
/// Setup as a full-screen flow (ESP-139 boards 01, 03 and 04). No tab bar.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var setupStart: SetupStart?
    @State private var settings: SettingsStart?
    @State private var homePath: [HomeRoute] = []
    @State private var voiceOpen = false

    struct SetupStart: Identifiable { var index: Int; var id: Int { index } }
    struct SettingsStart: Identifiable { let id = UUID(); var path: [SettingsRoute] }

    var body: some View {
        NavigationStack(path: $homePath) {
            HomeView(openSetup: openSetup, openSettings: { settings = SettingsStart(path: []) })
        }
        .environment(\.openVoice, { voiceOpen = true })
        .tint(.white)
        .sheet(item: $settings) { start in
            SettingsView(start: start.path, openSetup: { settings = nil; Task { try? await Task.sleep(for: .milliseconds(350)); openSetup() } })
        }
        .fullScreenCover(item: $setupStart) { start in SetupView(start: start.index) }
        .sheet(isPresented: $voiceOpen) { VoiceView(close: { voiceOpen = false }).tint(Site.blue) }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { model.becameActive() } else if phase == .background { model.wentToBackground() }
        }
        // A poki://voice link opens Voice; any other tap on the Live Activity brings Home to the front.
        // Neither interrupts pairing: it stays on the pairing step, where the PIN is.
        .onOpenURL { url in
            AppLog.shared.add("app", "opened by link poki://\(url.host() ?? "")")
            guard !model.pairingUnderWay else { return }
            let wasCovered = settings != nil
            settings = nil; setupStart = nil; homePath = []
            if url.host() == "voice" {
                model.voice.open(url)
                presentVoice(after: wasCovered)
            } else {
                voiceOpen = false
            }
        }
        .onAppear(perform: openLaunchScreen)
        #if DEBUG
        // Development builds: `-pokiVoiceLink "poki://voice?…"` at launch starts a silent test run.
        .task {
            if let link = UserDefaults.standard.string(forKey: "pokiVoiceLink"), let url = URL(string: link), url.host() == "voice" {
                voiceOpen = true
                model.voice.openAtLaunch(url)
            }
        }
        #endif
    }

    /// A sheet cannot replace another in the same moment: Settings is given time to close first.
    private func presentVoice(after wasCovered: Bool) {
        guard wasCovered else { voiceOpen = true; return }
        Task { try? await Task.sleep(for: .milliseconds(350)); voiceOpen = true }
    }

    private func openSetup() { setupStart = SetupStart(index: SetupView.firstOpen(model)) }

    /// `-pokiScreen setup` (voice, connect, debug, activity) opens that screen at launch, for the build's
    /// screenshots; `-pokiSetupStep 3` opens setup at that step.
    private func openLaunchScreen() {
        let defaults = UserDefaults.standard
        switch defaults.string(forKey: "pokiScreen") {
        case "setup":
            let step = defaults.integer(forKey: "pokiSetupStep")
            setupStart = SetupStart(index: step > 0 ? min(step, SetupStep.allCases.count) - 1 : SetupView.firstOpen(model))
        case "connect", "settings": settings = SettingsStart(path: [])
        case "debug": settings = SettingsStart(path: [.diagnostics])
        case "activity": settings = SettingsStart(path: [.diagnostics, .activityPreview])
        case "connector": settings = SettingsStart(path: model.identity.secrets.first.map { [.connector($0)] } ?? [])
        case "voice": voiceOpen = true
        case "steps": homePath = [.steps]
        case "status": homePath = [.status]
        default: break
        }
    }
}
