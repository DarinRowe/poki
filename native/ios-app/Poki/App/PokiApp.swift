import SwiftUI

@main
struct PokiApp: App {
    @State private var model: AppModel
    @State private var chat: ChatModel

    init() {
        // PokiLauncher (Rust) and the relay write to sockets the other side may have closed. In an app,
        // unlike a Rust executable, nothing ignores SIGPIPE, and it would end the whole app.
        signal(SIGPIPE, SIG_IGN)
        #if DEBUG && targetEnvironment(simulator)
        TestCredential.importIfGiven()
        #endif
        let model = AppModel()
        _model = State(initialValue: model)
        let chat = ChatModel(app: model)
        _chat = State(initialValue: chat)
        AskPoki.install(app: model, chat: chat)
    }

    var body: some Scene {
        WindowGroup {
            RootView().environment(model).environment(chat)
        }
    }
}

/// Chat and Voice side by side, a swipe apart (ESP-171 "对标 iMessage" boards). Poki's details open from
/// the picture on top, like a contact in Messages; settings and setup open from there or from the chat.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(ChatModel.self) private var chat
    @Environment(\.scenePhase) private var scenePhase
    @State private var page = RootPage.chat
    @State private var home: [HomeRoute] = []
    @State private var setupStart: SetupStart?
    @State private var settings: SettingsStart?
    @State private var details: DetailsStart?

    struct SetupStart: Identifiable { var index: Int; var id: Int { index } }
    struct SettingsStart: Identifiable { let id = UUID(); var path: [SettingsRoute] }
    struct DetailsStart: Identifiable { let id = UUID(); var path: [DetailsRoute] = [] }
    /// Sessions is the first page; Poki's chat and an agent's session open over it, like a conversation
    /// in Messages.
    enum HomeRoute: Hashable { case chat, session(String) }

    var body: some View {
        TabView(selection: $page) {
            NavigationStack(path: $home) {
                SessionsView(openChat: { home = [.chat] }, openSession: { home = [.session($0)] },
                             openModel: { details = DetailsStart(path: [.model]) },
                             openConnectors: { settings = SettingsStart(path: []) },
                             openDetails: { details = DetailsStart() }, openVoice: { withAnimation { page = .voice } },
                             openSetup: openSetup)
                    .navigationDestination(for: HomeRoute.self) { route in
                        switch route {
                        case .chat:
                            ChatView(openDetails: { details = DetailsStart() }, openVoice: { withAnimation { page = .voice } },
                                     openSetup: openSetup, openModel: { details = DetailsStart(path: [.model]) },
                                     back: { home = [] })
                        case .session(let id):
                            SessionView(id: id, back: { home = [] })
                        }
                    }
            }
                .tag(RootPage.chat)
            VoicePage(openDetails: { details = DetailsStart() }, openVoiceSettings: { settings = nil; details = DetailsStart() },
                      select: { target in withAnimation { page = target } })
                .tag(RootPage.voice)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // The pages keep the safe area for their content and draw their own colour behind the status bar.
        .ignoresSafeArea()
        .background((page == .voice ? Site.blue : Color(.systemBackground)).ignoresSafeArea())
        .fullScreenCover(item: $details) { start in
            PokiDetailsView(openVoice: { withAnimation { page = .voice } }, openSetup: openSetup, start: start.path)
        }
        .sheet(item: $settings) { start in
            SettingsView(start: start.path, openSetup: { settings = nil; Task { try? await Task.sleep(for: .milliseconds(350)); openSetup() } })
        }
        .fullScreenCover(item: $setupStart) { start in SetupView(start: start.index) }
        .task { InProcessProbe.shared.startFromLaunchArguments(model: model) }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { model.becameActive(); AskPoki.refresh() } else if phase == .background { model.wentToBackground() }
        }
        // A tap on the Live Activity brings the chat to the front; `poki://voice` only shows the voice page.
        .onOpenURL { url in
            AppLog.shared.add("app", "opened by link poki://\(url.host() ?? "")")
            // Pairing is not interrupted: it stays on the pairing step, where the PIN is.
            guard !model.pairingUnderWay else { return }
            settings = nil; setupStart = nil; details = nil
            // A pairing file or a setup link (from Poki Setup on a computer, AirDrop or Files) opens
            // setup at that step, where the result is shown.
            if let step = model.open(link: url) {
                page = .chat
                setupStart = SetupStart(index: SetupStep.shown.firstIndex(of: step) ?? 0)
            } else if url.host() == "voice" { page = .voice; model.voice.open(url) } else { page = .chat; home = [.chat] }
        }
        .onAppear(perform: openLaunchScreen)
        .task {
            #if DEBUG
            // Development builds: `-pokiVoiceLink "poki://voice?…"` at launch starts a silent test run.
            if let link = UserDefaults.standard.string(forKey: "pokiVoiceLink"), let url = URL(string: link), url.host() == "voice" {
                page = .voice
                model.voice.openAtLaunch(url)
            }
            #endif
        }
    }

    private func openSetup() { setupStart = SetupStart(index: SetupView.firstOpen(model)) }

    /// `-pokiScreen setup` (connect, debug, activity, details, model, voice…) opens that screen at launch,
    /// for the build's screenshots; `-pokiSetupStep 3` opens setup at that step.
    private func openLaunchScreen() {
        let defaults = UserDefaults.standard
        // `-pokiVoiceBridge <address>`: the voice bridge address, from the Mac that launches the app (only a
        // developer connection can pass launch arguments). It never turns on the microphone.
        if let address = defaults.string(forKey: "pokiVoiceBridge") { _ = model.voice.setBridge(address) }
        // A sample conversation (`-pokiChat working`) opens in the chat itself.
        if defaults.string(forKey: "pokiChat") != nil { home = [.chat] }
        switch defaults.string(forKey: "pokiScreen") {
        case "chat": home = [.chat]
        case "session": if let first = SessionStore.shared.ordered.first(where: { $0.kind != .poki }) { home = [.session(first.id)] }
        case "setup":
            let step = defaults.integer(forKey: "pokiSetupStep")
            setupStart = SetupStart(index: step > 0 ? min(step, SetupStep.shown.count) - 1 : SetupView.firstOpen(model))
        case "connect", "settings": settings = SettingsStart(path: [])
        case "debug": settings = SettingsStart(path: [.diagnostics])
        case "activity": settings = SettingsStart(path: [.diagnostics, .activityPreview])
        case "connector": settings = SettingsStart(path: model.identity.secrets.first.map { [.connector($0)] } ?? [])
        case "details", "status": details = DetailsStart()
        case "model": details = DetailsStart(path: [.model])
        case "steps": details = DetailsStart(path: [.history])
        case "voice": page = .voice
        default: break
        }
    }
}
