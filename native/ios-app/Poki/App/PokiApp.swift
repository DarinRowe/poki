import PokiCore
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
        // A memory backup Poki Setup put back (Documents/AgentBackup) is merged in before any agent asks.
        _ = RoutineStore.shared.importRestoredBackup()
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

/// Two tabs, as a native iPhone app has them: Chats (the Sessions list, Poki's chat and an agent's session
/// over it, like Messages) and Status (Poki's run status, model, history and settings). Voice lives inside
/// the chat: a live conversation button and dictation into the message field.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(ChatModel.self) private var chat
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = RootTab.chats
    @State private var home = NavigationPath()
    /// The Agents and Setup tabs' pages, pushed; nothing is an overlay.
    @State private var agents = NavigationPath()
    @State private var setup = NavigationPath()

    /// Sessions is the first page; Poki's chat and an agent's session open over it, like a conversation
    /// in Messages; setup's checklist and its items are pushed there too.
    enum HomeRoute: Hashable { case chat, session(String), setup }
    enum RootTab: Hashable { case chats, agents, setup }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $home) {
                SessionsView(openChat: { home = NavigationPath([HomeRoute.chat]) }, openSession: { home = NavigationPath([HomeRoute.session($0)]) },
                             openModel: { openAgents(AgentsRoute.accounts) },
                             openConnectors: { tab = .agents; agents = NavigationPath() },
                             openDetails: { tab = .agents }, openVoice: openLiveVoice,
                             openSetup: openSetup)
                    .navigationDestination(for: HomeRoute.self) { route in
                        switch route {
                        case .chat:
                            ChatView(openDetails: { tab = .agents }, openVoice: openLiveVoice,
                                     openSetup: openSetup, openModel: { openAgents(AgentsRoute.accounts) },
                                     back: { home = NavigationPath() })
                        case .session(let id):
                            SessionView(id: id, back: { home = NavigationPath() })
                        case .setup:
                            SetupChecklist()
                        }
                    }
                    .navigationDestination(for: SetupStep.self) { SetupStepPage(step: $0) }
            }
            .tabItem { Label(String(localized: "Poki"), systemImage: "bubble.left.and.bubble.right.fill") }
            .tag(RootTab.chats)

            AgentsView(path: $agents, openSession: openRun)
                .tabItem { Label("Agents", systemImage: "point.3.connected.trianglepath.dotted") }
                .tag(RootTab.agents)

            SetupTab(path: $setup)
                .tabItem { Label("Setup", systemImage: "checklist") }
                .badge(model.setupComplete ? 0 : SetupStep.shown.filter { !model.isDone($0) }.count)
                .tag(RootTab.setup)
        }
        // A sidebar on iPad (and beside another app in Split View), the tab bar on iPhone.
        .tabViewStyle(.sidebarAdaptable)
        .task { InProcessProbe.shared.startFromLaunchArguments(model: model) }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { model.becameActive(); AskPoki.refresh() } else if phase == .background { model.wentToBackground() }
        }
        // A tap on the Live Activity brings the chat to the front; `poki://voice` opens the chat too (it
        // never turns on the microphone).
        .onOpenURL { url in
            AppLog.shared.add("app", "opened by link poki://\(url.host() ?? "")")
            // Pairing is not interrupted: it stays on the pairing step, where the PIN is.
            guard !model.pairingUnderWay else { return }
            // A pairing file or a setup link (from Poki Setup on a computer, AirDrop or Files) opens
            // setup at that step, where the result is shown.
            if let step = model.open(link: url) {
                tab = .setup
                setup = NavigationPath([step])
            } else {
                if url.host() == "voice" { model.voice.open(url) }
                tab = .chats; home = NavigationPath([HomeRoute.chat])
            }
        }
        .onAppear(perform: openLaunchScreen)
        .task {
            #if DEBUG
            // Development builds: `-pokiVoiceLink "poki://voice?…"` at launch starts a silent test run.
            if let link = UserDefaults.standard.string(forKey: "pokiVoiceLink"), let url = URL(string: link), url.host() == "voice" {
                tab = .chats; home = NavigationPath([HomeRoute.chat])
                model.voice.openAtLaunch(url)
            }
            #endif
        }
    }

    /// The live voice conversation runs inside Poki's chat: the chat opens and the conversation starts.
    private func openLiveVoice() {
        tab = .chats
        home = NavigationPath([HomeRoute.chat])
        if !model.voice.isOn, model.voice.canTalkLive {
            // Taps that send, pay, delete or call ask for the person's OK, also by notification.
            ApprovalNotice.requestPermission()
            Task { await model.voice.start() }
        }
    }

    /// Setup's checklist, on the Chats page.
    private func openSetup() {
        tab = .chats
        home = NavigationPath([HomeRoute.setup])
    }

    /// A run from the Activity Log: Poki's own chat or an outside agent's session, in Chats.
    private func openRun(_ id: String) {
        tab = .chats
        if let session = SessionStore.shared.session(id), session.kind == .poki {
            if session.id != chat.sessionID { chat.restore(session) }
            home = NavigationPath([HomeRoute.chat])
        } else {
            home = NavigationPath([HomeRoute.session(id)])
        }
    }


    /// `-pokiScreen setup` (connect, debug, activity, details, model, voice…) opens that screen at launch,
    /// for the build's screenshots; `-pokiSetupStep 3` opens setup at that step.
    private func openLaunchScreen() {
        let defaults = UserDefaults.standard
        // `-pokiVoiceBridge <address>`: the voice bridge address, from the Mac that launches the app (only a
        // developer connection can pass launch arguments). It never turns on the microphone.
        if let address = defaults.string(forKey: "pokiVoiceBridge") { _ = model.voice.setBridge(address) }
        // A sample conversation (`-pokiChat working`) opens in the chat itself.
        if defaults.string(forKey: "pokiChat") != nil { home = NavigationPath([HomeRoute.chat]) }
        switch defaults.string(forKey: "pokiScreen") {
        case "chat": home = NavigationPath([HomeRoute.chat])
        case "session": if let first = SessionStore.shared.ordered.first(where: { $0.kind != .poki }) { home = NavigationPath([HomeRoute.session(first.id)]) }
        case "setup":
            let step = defaults.integer(forKey: "pokiSetupStep")
            tab = .setup
            setup = step > 0 ? NavigationPath([SetupStep.shown[min(step, SetupStep.shown.count) - 1]]) : NavigationPath()
        case "connect", "settings": tab = .agents
        case "debug": tab = .setup; setup = NavigationPath([SettingsRoute.diagnostics])
        case "activity": tab = .setup; setup = NavigationPath([SettingsRoute.diagnostics, SettingsRoute.activityPreview])
        case "connector":
            tab = .agents
            if let first = model.identity.secrets.first { agents = NavigationPath([SettingsRoute.connector(first)]) }
        case "details", "status": tab = .agents
        case "model": openAgents(.accounts)
        case "steps": openAgents(.activityLog)
        case "voice": home = NavigationPath([HomeRoute.chat])
        default: break
        }
    }
}
