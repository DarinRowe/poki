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

    @Environment(\.horizontalSizeClass) private var width
    /// In a wide window (iPad, the inner display of iPhone Duo, a large Split View or Stage Manager
    /// window) the Poki tab is split: sessions and controls on the left, the chat on the right.
    @State private var wide: HomeRoute = .chat

    private func show(_ route: HomeRoute) {
        wide = route
        home = NavigationPath([route])
    }

    private var sessions: some View {
        SessionsView(openChat: { show(HomeRoute.chat) }, openSession: { show(HomeRoute.session($0)) },
                     openModel: { openAgents(AgentsRoute.accounts) },
                     openConnectors: { tab = .agents; agents = NavigationPath() },
                     openDetails: { tab = .agents }, openVoice: openLiveVoice,
                     openSetup: openSetup)
    }

    @ViewBuilder private func page(_ route: HomeRoute, split: Bool) -> some View {
        switch route {
        case .chat:
            ChatView(openDetails: { tab = .agents }, openVoice: openLiveVoice,
                     openSetup: openSetup, openModel: { openAgents(AgentsRoute.accounts) },
                     back: split ? nil : { home = NavigationPath() })
        case .session(let id):
            SessionView(id: id, back: { home = NavigationPath() }, hidesTabBar: !split)
        case .setup:
            SetupChecklist()
        }
    }

    @ViewBuilder private var pokiTab: some View {
        if width == .regular {
            NavigationSplitView {
                sessions
                    .navigationDestination(for: SetupStep.self) { SetupStepPage(step: $0) }
            } detail: {
                NavigationStack {
                    page(wide, split: true).id(wide)
                        .navigationDestination(for: SetupStep.self) { SetupStepPage(step: $0) }
                }
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            NavigationStack(path: $home) {
                sessions
                    .navigationDestination(for: HomeRoute.self) { page($0, split: false) }
                    .navigationDestination(for: SetupStep.self) { SetupStepPage(step: $0) }
            }
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            pokiTab
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
        .task { InProcessProbe.shared.startFromLaunchArguments(model: model) }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { model.becameActive(); AskPoki.refresh() } else if phase == .background { model.wentToBackground() }
        }
        // A tap on the Live Activity opens the screen its state is about (ActivityFace.link): the chat,
        // the setup step, or the Activity Log for a problem; `poki://voice` opens the chat too (it
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
            } else if url.host() == "setup", !url.absoluteString.contains("relay=") {
                // The Live Activity during setup: the Setup tab.
                tab = .setup
            } else if url.host() == "log" {
                // The Live Activity's problem: what went wrong is in the Activity Log.
                openAgents(.activityLog)
            } else {
                if url.host() == "voice" { model.voice.open(url) }
                tab = .chats; show(HomeRoute.chat)
            }
        }
        .onAppear(perform: openLaunchScreen)
        .task {
            #if DEBUG
            // Development builds: `-pokiVoiceLink "poki://voice?…"` at launch starts a silent test run.
            if let link = UserDefaults.standard.string(forKey: "pokiVoiceLink"), let url = URL(string: link), url.host() == "voice" {
                tab = .chats; show(HomeRoute.chat)
                model.voice.openAtLaunch(url)
            }
            #endif
        }
    }

    /// A page of the Agents tab: accounts, voice, the Activity Log.
    private func openAgents(_ route: AgentsRoute) {
        tab = .agents
        agents = NavigationPath([route])
    }

    /// The live voice conversation runs inside Poki's chat: the chat opens and the conversation starts.
    private func openLiveVoice() {
        tab = .chats
        show(HomeRoute.chat)
        if !model.voice.isOn, model.voice.canTalkLive {
            // Taps that send, pay, delete or call ask for the person's OK, also by notification.
            ApprovalNotice.requestPermission()
            Task { await model.voice.start() }
        }
    }

    /// Setup's checklist, on the Chats page.
    private func openSetup() {
        tab = .chats
        show(HomeRoute.setup)
    }

    /// A run from the Activity Log: Poki's own chat or an outside agent's session, in Chats.
    private func openRun(_ id: String) {
        tab = .chats
        if let session = SessionStore.shared.session(id), session.kind == .poki {
            if session.id != chat.sessionID { chat.restore(session) }
            show(HomeRoute.chat)
        } else {
            show(HomeRoute.session(id))
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
        if defaults.string(forKey: "pokiChat") != nil { show(HomeRoute.chat) }
        switch defaults.string(forKey: "pokiScreen") {
        case "chat": show(HomeRoute.chat)
        case "session": if let first = SessionStore.shared.ordered.first(where: { $0.kind != .poki }) { show(HomeRoute.session(first.id)) }
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
        case "voice": show(HomeRoute.chat)
        default: break
        }
    }
}
