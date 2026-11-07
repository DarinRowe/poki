import PokiCore
import SwiftUI
import UIKit

/// The app's state and the glue between PokiCore, PokiLauncher, the loopback, the Live Activity and
/// approvals. One instance, owned by PokiApp.
@MainActor
@Observable
final class AppModel {
    var setup = SetupState.load() { didSet { setup.save() } }
    let identity = RelayIdentity()
    /// The person's own relay (Connect). Poki has no default relay and sends nothing until one is set.
    private(set) var relayAddress = RelayAddress.saved
    let loopback = LoopbackMonitor()
    let tunnel = LoopbackTunnel()
    let background = BackgroundKeeper()
    let diskImage = DiskImageStore()
    let voice: VoiceModel
    private(set) var runner = RunnerStatus.idle
    private(set) var relayStatus = RelayStatus.off
    private(set) var sessionOn = false
    private(set) var activityText = "Idle"
    private(set) var lastAction: String?
    private(set) var approvals: [PendingApproval] = []
    private(set) var pairing: PairingEvent?
    private(set) var problem: String?
    /// The agent's recent actions, newest last, for the home screen.
    private(set) var recentSteps: [RecentStep] = []
    /// The app the agent is in, from its last step.
    private(set) var currentApp: String?
    /// The runner is stopped until the next agent request (idle, or the owner tapped Stop runner).
    private(set) var runnerPaused = false
    /// Stop the runner after this long without agent activity; 0 never stops it.
    /// Two minutes by default: an agent can think for a minute between steps of a long task, and the
    /// runner must not stop (and the banner flash) in the middle of it.
    var idleStopSeconds: Int = UserDefaults.standard.object(forKey: "idleStopSeconds.v4") as? Int ?? 60 {
        didSet { UserDefaults.standard.set(idleStopSeconds, forKey: "idleStopSeconds.v4"); log.add("runner", "idle stop set to \(idleStopSeconds) s") }
    }
    /// Poki was on when it last ran; it turns itself on again at launch.
    private var wantsOn: Bool {
        get { UserDefaults.standard.bool(forKey: "wantsOn") }
        set { UserDefaults.standard.set(newValue, forKey: "wantsOn") }
    }
    /// The setup step the Live Activity is guiding, if any.
    private(set) var guiding: SetupStep?
    /// The pairing file, if it is really there. The path is never stored: the app's container moves
    /// when Poki is installed again, and a stored path then points at nothing.
    var pairingPath: String? { FileManager.default.fileExists(atPath: AppFiles.pairingFile.path) ? AppFiles.pairingFile.path : nil }
    /// Why the phone refused the pairing the last time the runner started, until it is accepted again.
    private(set) var pairingTrouble: String?
    /// When the phone last accepted the pairing (the runner got past the pairing step).
    private(set) var pairingVerifiedAt: Date?
    /// The runner has been launching for a while: iOS may be asking for the passcode.
    private(set) var passcodeHint = false
    /// The hand-off the agent asked the owner for, while it waits (shown on the home screen too).
    private(set) var handoffText: String?
    private var launchingSince: Date?
    private var endCheck = 0
    private var lastAgentActivity = Date()
    /// The agent's step now running (its label and start), for the foreground check above.
    private var stepUnderWay: (summary: String, started: Date)?
    private var idleTimer: Timer?
    private var launcherConfig: LauncherConfig?

    let host = AppCoreHost()
    /// Poki Runner or Poki's own process, fixed for this launch (Debug tab).
    let automationPath = AutomationPath.current
    private let core: LiveCore
    private let launcher: RunnerLauncher
    private let pairer: DevicePairing
    private let pairingKeepAlive = KeepAlive()
    private let activity = ActivityController()
    let log = AppLog.shared
    private var eventsTask: Task<Void, Never>?
    private var sessionStartTask: Task<Void, Never>?
    private(set) var sessionStarting = false

    var connectionInUse: Bool {
        if sessionOn || sessionStarting { return true }
        return pairingUnderWay
    }

    var connectionMethod: SetupState.Loopback {
        if setup.loopback != .none { return setup.loopback }
        // The external app is the way (ESP-168); the built-in connection is only ever chosen.
        return .proxy
    }

    init(launcher: RunnerLauncher = RustLauncher(), pairer: DevicePairing = RustPairing()) {
        ActivityController.endAll()
        let core = LiveCore(host: host, transport: automationPath == .inProcess ? InProcessWDA(screen: UIScreen.main.bounds.size) : URLSessionTransport())
        self.core = core
        // Voice taps get the same rules and approval card as an agent's `do`.
        voice = VoiceModel(clearTap: { text, bundle, name in await core.clearTap(on: text, inApp: bundle, named: name, waiting: VoiceModel.approvalWait) },
                           phoneTool: { name, arguments in
                               let result = await core.tool(name, arguments: arguments)
                               return (result.text, result.isError)
                           },
                           holdMicrophone: { [background] on in on ? background.pauseAudio() : background.resumeAudio() })
        self.launcher = launcher
        self.pairer = pairer
        host.update(key: identity.signingKey, hashes: identity.accessHashes)
        // PokiCore asks for a restart after two silent requests in a row. A slow gesture can be one of
        // them while the runner is fine, so the runner is asked first; only a runner that does not
        // answer is started again (each restart costs seconds and flashes the automation banner).
        host.onRestart {
            Task.detached {
                let answers = await RunnerProbe.answers()
                await MainActor.run { AppLog.shared.add("runner", answers ? "PokiCore asked for a restart; the runner answers, so it was kept" : "PokiCore asked for a restart; the runner does not answer: restarting it") }
                if !answers { launcher.restart() }
            }
        }
        host.onWake { [weak self] in Task { @MainActor in self?.wakeRunner() } }
        // Allow and Deny on the Live Activity run in this process and come straight here.
        ApprovalIntentBridge.install { [weak self] decision in
            guard let self else { return false }
            self.decide(decision)
            return true
        }
        listenForApprovals()
        // One pump for the app's whole life. Cancelling a task that reads an AsyncStream ends the
        // stream for good, so a pump per session would go silent after the first Turn off (no steps,
        // no approvals, no relay state in the log, which is what happened on the phone).
        eventsTask = Task { [weak self, core] in
            for await event in core.events { self?.handle(event) }
        }
        loopback.onChange = { [weak self] old, new in self?.loopbackChanged(from: old, to: new) }
        if !diskImage.isReady { Task { await diskImage.download() } }
        if UserDefaults.standard.string(forKey: "pokiSample") != nil { loadSample() }
        NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appWillTerminate() }
        }
        // Installed over the local-VPN build (both use one bundle ID): this build has only external
        // connections, so a saved built-in choice becomes the external one. Otherwise Setup showed the
        // step done while Turn on said this build has no local VPN.
        if setup.loopback == .builtIn, !tunnel.available {
            setup.loopback = .proxy
            setup.save()
            log.add("loopback", "this build has no built-in connection: the saved choice is now an external one")
        }
    }

    /// Poki came to the front: turn on again if it was on, check the loopback live, and finish a
    /// setup step the person just did in Settings.
    func becameActive() {
        inFront = true
        loopback.resume()
        // Poki in front while an agent's step is under way: nobody opened it on purpose. A tap near the
        // top of the screen hit the expanded Dynamic Island (iOS opens the activity's app), or the agent
        // tapped the activity's own label in the tree. Logged so the phone log shows it; PokiCore sends
        // the agent back to the app it was in.
        if sessionOn, let step = stepUnderWay, Date().timeIntervalSince(step.started) < 20 {
            log.add("app", "Poki came to the front during a step (\(step.summary)): a tap hit the Live Activity")
        }
        Task {
            await tunnel.refresh()
            if wantsOn, !sessionOn, pairingPath != nil, diskImage.isReady { startSession(reconnectLocal: false) }
        }
        if let step = guiding, isDone(step) { stopGuide() }
    }

    /// In the background the loopback is still watched while Poki is on (the agent's runner depends on
    /// it): every 6 s, light enough for the location-kept background time.
    func wentToBackground() { inFront = false; sessionOn ? loopback.resume(every: 6) : loopback.pause() }
    private var inFront = true

    /// Poki is being closed: end the runner now (the launcher kills its process) instead of leaving
    /// iOS's automation banner up for half a minute. iOS gives a few seconds for this.
    private func appWillTerminate() {
        // The Live Activity goes with the app; the pause below gives its end time to reach iOS.
        ActivityController.endAll()
        guard sessionOn else { Thread.sleep(forTimeInterval: 0.5); return }
        log.add("app", "Poki is closing: ending the runner")
        launcher.stop()
        Thread.sleep(forTimeInterval: 2.5)
    }

    var deviceName: String { UIDevice.current.name }

    /// `-pokiSample B` (YES is B), `C` or `PIN`: the home screen states of ESP-139 board 01 with sample
    /// steps and an approval, only for the build's screenshots. Nothing is started: B and D look like a
    /// session at work, C like one standing by (the loopback check stays live, so a simulator shows it
    /// off). A sample relay address (not saved) and, on a simulator, two agents are added when there are none.
    private func loadSample() {
        let scene = UserDefaults.standard.string(forKey: "pokiSample")?.uppercased() ?? "B"
        // PIN: setup's pairing page with a sample code, as if Settings had asked for one.
        if scene == "PIN" { pairing = .pin("482913"); return }
        let now = Date()
        let messages = String(localized: "Messages")
        // The sample relay is not saved. Sample agents go into the keychain, so only a simulator gets them.
        if relayAddress == nil { relayAddress = RelayAddress("https://your-relay.example") }
        #if targetEnvironment(simulator)
        if identity.secrets.isEmpty {
            _ = addConnector(name: "Claude")
            _ = addConnector(name: "Codex")
        }
        #endif
        Thumbnail.previewImage = ActivityPreview.sampleScreen()
        sessionOn = true
        relayStatus = .ready
        currentApp = messages
        if scene == "C" {
            runnerPaused = true
            runner = RunnerStatus(state: "standby", detail: "It starts when an agent asks.")
            recentSteps = (0..<12).map { i in
                RecentStep(text: String(localized: "Tap “Send”"), app: messages, at: now.addingTimeInterval(Double(i - 11) * 84 / 11 - 300))
            }
            return
        }
        runner = RunnerStatus(state: "running")
        recentSteps = [
            RecentStep(text: String(localized: "Open Messages"), app: String(localized: "Home Screen"), at: now.addingTimeInterval(-70)),
            RecentStep(text: String(localized: "Tap the chat with Mom"), app: messages, at: now.addingTimeInterval(-52)),
            RecentStep(text: String(localized: "Type “On my way”"), app: messages, at: now.addingTimeInterval(-41)),
            RecentStep(text: "Tap at 212, 640", app: messages, failure: "failed: nothing changed", at: now.addingTimeInterval(-30)),
        ]
        activityText = String(localized: "Tap “Send”")
        approvals = [PendingApproval(id: "sample", app: messages, summary: String(localized: "Send “On my way” to Mom"),
                                     reason: "sending a message (\"send\")", expires: now.addingTimeInterval(25))]
    }

    // MARK: Session

    func chooseConnection(_ method: SetupState.Loopback) {
        guard !connectionInUse, !tunnel.busy else { return }
        if method == .proxy { tunnel.disconnect() }
        setup.loopback = method
        setup.proxyApp = nil
        loopback.check()
    }

    func startSession(reconnectLocal: Bool = true) {
        guard !sessionOn, !sessionStarting else { return }
        if setup.loopback == .none {
            problem = "Choose and enable a local connection first (Setup)."
            return
        }
        if setup.loopback == .builtIn, !tunnel.connected {
            guard reconnectLocal else {
                problem = "The local connection is off. Turn Poki on to reconnect, or choose an external connection in Setup."
                return
            }
            sessionStarting = true
            sessionStartTask = Task {
                defer { sessionStarting = false; sessionStartTask = nil }
                do {
                    try await tunnel.connect()
                    try Task.checkCancellation()
                    loopback.check()
                    beginSession()
                } catch is CancellationError { }
                catch { problem = error.localizedDescription }
            }
        } else { beginSession() }
    }

    private func beginSession() {
        guard !sessionOn else { return }
        problem = nil
        guard let pairing = pairingPath else { problem = "Pair this iPhone first (Setup)."; return }
        guard let relay = relayAddress else { problem = Self.noRelay; return }
        if !inFront { loopback.resume(every: 6) }
        guard diskImage.isReady, diskImage.recheck() else {
            problem = "The developer disk image is not downloaded yet (Setup > Pair). It is needed once."
            Task { await diskImage.download() }
            return
        }
        log.add("session", "turned on")
        background.start()
        ApprovalNotice.requestPermission()
        stopGuide()
        activity.start(deviceName: deviceName)
        log.add("activity", activity.isRunning ? "Live Activity started" : "Live Activity not running: \(activity.lastError ?? "unknown reason")")
        sessionOn = true
        wantsOn = true
        launcherConfig = LauncherConfig(pairing_file: pairing, ddi_dir: AppFiles.ddiDirectory.path, in_process: automationPath == .inProcess)
        lastAgentActivity = Date()
        // The runner (and with it iOS's automation banner) starts only when an agent asks.
        standBy(reason: nil)
        core.start(relay: relay)
        idleTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in Task { @MainActor in self?.checkIdle() } }
    }

    func stopSession() {
        sessionStartTask?.cancel()
        wantsOn = false
        guard sessionOn else {
            if setup.loopback == .builtIn { tunnel.disconnect() }
            return
        }
        if !inFront { loopback.pause() }
        log.add("session", automationPath == .inProcess ? "turned off; the in-process session stays open until Poki exits" : "turned off: ending the runner")
        core.stop()
        launcher.stop()
        if setup.loopback == .builtIn { tunnel.disconnect() }
        if automationPath == .runner {
            Task { await RunnerProbe.shutdown() }
            confirmRunnerEnded()
        }
        idleTimer?.invalidate(); idleTimer = nil
        runnerPaused = false; host.setPaused(false)
        background.stop()
        activity.end()
        sessionOn = false
        runner = .idle
        relayStatus = .off
        activityText = "Idle"
    }

    func restartRunner() { launcher.restart() }

    private func launchRunner() {
        guard let launcherConfig else { return }
        do {
            try launcher.start(config: launcherConfig) { [weak self] status in Task { @MainActor in self?.runnerChanged(status) } }
        } catch { runnerChanged(RunnerStatus(state: "failed", detail: "\(error)")) }
    }

    /// Stops the runner, and with it iOS's automation banner, while the relay stays connected; the
    /// next agent request starts it again. From the Stop runner button, the Live Activity, or idle.
    func pauseRunner(reason: String = "Stopped") {
        guard sessionOn, !runnerPaused, approvals.isEmpty else { return }
        if automationPath == .inProcess {
            // XCTest keeps one shared session per process and cannot open a second one, so the
            // in-process session stays open (and with it the banner) until Poki exits.
            log.add("runner", "standing by: \(reason); the in-process session stays open, and the banner with it, until Poki exits")
            launcher.stop()
            standBy(reason: reason)
            return
        }
        log.add("runner", "stopping: \(reason)")
        // The runner is asked to shut itself down (it ends its test and exits) and the launcher's
        // session is closed; the launcher also ends the process through the developer services.
        Task { await RunnerProbe.shutdown() }
        launcher.stop()
        standBy(reason: reason)
        confirmRunnerEnded()
    }

    /// After a stop, watches the runner until it really ends (and with it the automation banner):
    /// once a second for 30 s. The log says how long it took. If it is still there after 10 s, the
    /// home screen says so, and the notice goes away by itself the moment the runner is gone.
    func confirmRunnerEnded() {
        endCheck += 1
        let check = endCheck
        Task { [weak self] in
            for second in 1...30 {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.endCheck == check else { return }
                // An agent asked for the runner again in the meantime: nothing to watch.
                if self.sessionOn, !self.runnerPaused { self.clearStuckNotice(); return }
                if !(await RunnerProbe.answers()) {
                    self.log.add("runner", "ended \(second) s after Stop")
                    self.clearStuckNotice()
                    return
                }
                // Still up: the shutdown may have queued behind a long read in the runner, or the
                // developer connection the launcher kills through was gone. Ask again.
                if second == 4 || second == 12 || second == 20 {
                    self.log.add("runner", "still answering \(second) s after Stop: asking again")
                    await RunnerProbe.shutdown()
                    self.launcher.stop()
                }
                if second == 10 {
                    self.log.add("runner", "still answering 10 s after Stop")
                    self.problem = Self.stuckNotice
                }
            }
            guard let self, self.endCheck == check else { return }
            self.log.add("runner", "still answering 30 s after Stop")
        }
    }

    private static let stuckNotice = "Poki Runner is still running after Stop. Swipe it away in the app switcher; the banner goes with it."
    private func clearStuckNotice() { if problem == Self.stuckNotice { problem = nil } }

    /// The runner is off and starts on the next agent request.
    private func standBy(reason: String?) {
        runnerPaused = true
        runner = RunnerStatus(state: "standby", detail: reason.map { "\($0). It starts again when an agent asks." } ?? "It starts when an agent asks.")
        host.update(runner: .starting("starting the runner"))
        host.setPaused(true)
        activityText = "Idle"
        activity.update { $0.runnerPaused = true; $0.phase = .idle; $0.headline = "Runner asleep"; $0.since = nil }
    }

    /// Starts a paused runner again (the next agent request, or the owner).
    func wakeRunner() {
        guard sessionOn, runnerPaused else { return }
        runnerPaused = false
        host.setPaused(false)
        lastAgentActivity = Date()
        log.add("runner", "an agent asked: starting the runner")
        activity.update { $0.runnerPaused = false; $0.phase = .working; $0.headline = "Starting the runner"; $0.since = Date() }
        launchRunner()
    }

    private func checkIdle() {
        passcodeHint = runner.state == "launching" && launchingSince.map { Date().timeIntervalSince($0) > 10 } == true
        guard sessionOn, !runnerPaused, idleStopSeconds > 0, approvals.isEmpty, activityText == "Idle" else { return }
        if Date().timeIntervalSince(lastAgentActivity) >= Double(idleStopSeconds) {
            pauseRunner(reason: "Stopped after \(idleStopSeconds / 60 > 0 ? "\(idleStopSeconds / 60) min" : "\(idleStopSeconds) s") without agent activity")
        }
    }

    /// The loopback came or went. Going: logged with the time, and the agent's status says so instead
    /// of "Checking pairing". Back: the launcher tries at once instead of waiting out its backoff
    /// (the runner dies with the tunnel, so every drop costs a restart).
    func loopbackChanged(from old: LoopbackMonitor.State, to new: LoopbackMonitor.State) {
        let wasWorking = { if case .working = old { true } else { false } }()
        if wasWorking, !loopback.isWorking {
            log.add("loopback", "dropped: 10.7.0.1 stopped answering (\(loopback.state)); the runner cannot survive this")
        } else if !wasWorking, loopback.isWorking, old != .checking {
            log.add("loopback", "back: 10.7.0.1 answers again" + (sessionOn && !runner.isRunning && !runnerPaused ? "; starting the runner now" : ""))
            if sessionOn, !runner.isRunning, !runnerPaused { launcher.restart() }
        }
        if sessionOn { host.update(runner: coreState(of: runner)) }
    }

    /// The runner's state as the agent reads it. While the loopback is down, every pre-launch state
    /// is the same thing: waiting for the tunnel, said with the time it went and what to do.
    func coreState(of status: RunnerStatus) -> RunnerState {
        if status.code == "passcode" {
            return .starting("the phone is asking the owner for the passcode (iOS does this once before the first automation after a restart or a force quit); the Live Activity tells the owner; the runner starts the moment it is entered. Call again in about 10 s; nothing is lost and no action is needed from you")
        }
        let preLaunch = ["connecting", "pairing", "tunnel", "waiting_network", "standby", "idle"].contains(status.state)
        if preLaunch, !loopback.isWorking, loopback.state != .checking || status.state == "waiting_network" {
            if loopback.cellularRefused {
                let since = loopback.droppedAt.map { " since \(Self.clock.string(from: $0))" } ?? ""
                return .starting("waiting for Wi-Fi\(since): the phone has only cellular, and iOS refuses the developer services' loopback there. The owner connects Wi-Fi and opens Poki; the runner starts by itself, and once it runs the phone can switch back to cellular. Nothing on the phone changes meanwhile")
            }
            return .waitingForLoopback(since: loopback.droppedAt.map(Self.clock.string(from:)),
                                       tunnelWithoutAnswer: loopback.state == .noAnswer,
                                       connection: setup.loopback == .builtIn ? .builtIn : .external)
        }
        return status.coreState
    }
    private static let clock: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f }()

    func runnerChanged(_ status: RunnerStatus) {
        if status != runner { log.add("runner", "\(status.state)\(status.detail.map { ": \($0)" } ?? "")") }
        // Events from a launcher that was stopped for idle are old news.
        guard !runnerPaused else { return }
        // On the in-process path the session is opened as soon as the launcher is ready, so the
        // owner's one-time Automation Mode passcode comes when they turn Poki on, not mid-task.
        if status.state == "running", automationPath == .inProcess {
            DispatchQueue.global(qos: .userInitiated).async {
                let result = PKInProcess.shared().prepare()
                let ok = (result["ok"] as? Bool) == true
                Task { @MainActor in AppLog.shared.add("runner", ok ? "in-process session ready (generation \(result["generation"] ?? 0), \(String(format: "%.2f", result["seconds"] as? Double ?? 0)) s)" : "in-process session not ready: \(result["code"] ?? "unknown")") }
            }
        }
        switch status.state {
        case "launching", "running":
            // The phone accepted the pairing.
            if pairingTrouble != nil { log.add("pairing", "accepted again") }
            pairingTrouble = nil
            pairingVerifiedAt = Date()
            if status.state == "launching", runner.state != "launching" { launchingSince = Date() }
        case "failed" where status.fix?.contains("Pair again") == true:
            if pairingTrouble == nil { log.add("pairing", "refused: \(status.detail ?? "")") }
            pairingTrouble = status.detail ?? "The phone refused the pairing."
        default: break
        }
        if status.state != "launching" { launchingSince = nil; passcodeHint = false }
        if status.code == "passcode", runner.code != "passcode" {
            // iOS is asking for the passcode before the first UI automation after a restart. The
            // launcher waits minutes for it; the person is asked on the Live Activity, and the agent
            // reads a plain "starting" meanwhile (coreState).
            passcodeHint = true
            log.add("runner", "the runner has not answered for 12 s: asking the owner for the passcode on the Live Activity")
            activity.update { $0.phase = .handoff; $0.handoff = .init(id: Self.runnerPasscodeHandoff, kind: .runnerPasscode, text: nil, app: nil, since: Date()) }
        }
        if status.isRunning, activity.state.handoff?.id == Self.runnerPasscodeHandoff {
            activity.update { $0.handoff = nil; $0.phase = .idle; $0.headline = "Ready for the agent" }
        }
        if status.code == "ddi_bad", runner.code != "ddi_bad" {
            log.add("ddi", "the phone would not install the disk image: downloading it again")
            diskImage.redownload()
        }
        runner = status
        host.update(runner: coreState(of: status))
        if status.state == "failed" {
            let title = Self.problemText(status.fix ?? status.detail ?? "The runner stopped")
            activity.update { $0.phase = .problem; $0.label = "Runner Stopped"; $0.headline = title }
        } else if !status.isRunning {
            activity.update { $0.phase = .idle; $0.headline = status.title }
        } else if activity.state.phase == .problem || activity.state.phase == .idle || activity.state.headline == "Starting the runner" {
            activity.update { $0.phase = .idle; $0.headline = "Waiting for agent" }
        }
    }

    private func handle(_ event: ShellEvent) {
        // Events after Turn off (the core's own "stopped") are not for the screen.
        guard sessionOn else { return }
        switch event {
        case .relay(let status):
            if status != relayStatus { log.add("relay", "\(status)") }
            relayStatus = status
        case .toolStarted(_, let summary):
            lastAgentActivity = Date()
            stepUnderWay = (summary, Date())
            activityText = summary
            log.add("agent", "started: \(summary)")
            if problem?.hasPrefix("An approval ran out") == true { problem = nil }
            activity.update { state in
                if state.approval == nil {
                    if state.phase != .working || state.since == nil { state.since = Date() }
                    state.phase = .working
                }
                state.headline = summary
            }
        case .toolFinished(let summary, let delivery, let app, let thumbnail):
            lastAgentActivity = Date()
            stepUnderWay = nil
            lastAction = "\(summary) · \(delivery)"
            activityText = "Idle"
            let failed = delivery.hasPrefix("failed")
            log.add("agent", "\(failed ? "failed" : "done"): \(summary) · \(delivery.prefix(160))")
            if let app { currentApp = app }
            recentSteps.append(RecentStep(text: summary, app: app, failure: failed ? delivery : nil, at: Date()))
            if recentSteps.count > 20 { recentSteps.removeFirst(recentSteps.count - 20) }
            activity.record(step: summary, ok: !failed)
            activity.update { state in state.app = app ?? state.app }
            activity.setThumbnail(thumbnail)
        case .approvalRequested(let approval):
            approvals.append(approval)
            log.add("approval", "requested \(approval.id) in \(approval.app): \(approval.summary); Live Activity \(activity.isRunning ? "running" : "NOT running: \(activity.lastError ?? "no error")")")
            activity.update { $0.phase = .approval; $0.approval = approval; $0.headline = "Allow this step?" }
            // The Live Activity pops up for it by itself; the notification is for when it is not running.
            if !activity.isRunning { ApprovalNotice.post(approval) }
        case .approvalEnded(let id, let approved):
            approvals.removeAll { $0.id == id }
            log.add("approval", "ended \(id): \(approved.map { $0 ? "approved" : "denied" } ?? "expired or replaced")")
            if approved == nil { problem = "An approval ran out before you answered, so that step was not done. The agent can ask again." }
            ApprovalNotice.clear(id)
            activity.update { state in
                if state.approval?.id == id { state.approval = nil; state.phase = .working; state.headline = approved == true ? "Continuing" : "Step skipped" }
            }
        case .handoffRequested(let id, let kind, let text, let app):
            lastAgentActivity = Date()
            let shown = PokiActivityAttributes.Handoff.Kind(rawValue: kind) ?? .other
            handoffText = text ?? Self.handoffWording(shown)
            log.add("handoff", "the agent handed over \(id) (\(kind))\(app.map { " in \($0)" } ?? ""): \(handoffText ?? "")")
            activity.update { state in
                state.phase = .handoff
                state.handoff = .init(id: id, kind: shown, text: text, app: app, since: Date())
                state.headline = "Your turn"
                state.app = app ?? state.app
            }
        case .handoffEnded(let id, let how):
            lastAgentActivity = Date()
            log.add("handoff", "ended \(id): \(how)")
            handoffText = nil
            activity.update { state in
                if state.handoff?.id == id {
                    state.handoff = nil
                    state.phase = .working
                    state.headline = how == "done" ? "Carrying on" : "The agent carried on by itself"
                }
            }
        }
    }

    // MARK: Approvals

    /// Approvals from the app's own screen (the same path as the Live Activity's buttons).
    func resolve(_ approval: PendingApproval, approved: Bool) {
        core.resolveApproval(id: approval.id, approved: approved)
    }

    private func listenForApprovals() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(center, observer, { _, observer, _, _, _ in
            guard let observer else { return }
            let model = Unmanaged<AppModel>.fromOpaque(observer).takeUnretainedValue()
            Task { @MainActor in model.drainApprovals() }
        }, ApprovalMailbox.notification as CFString, nil, .deliverImmediately)
        CFNotificationCenterAddObserver(center, observer, { _, observer, _, _, _ in
            guard let observer else { return }
            let model = Unmanaged<AppModel>.fromOpaque(observer).takeUnretainedValue()
            Task { @MainActor in model.pauseRunner(reason: "Stopped from the Live Activity") }
        }, ApprovalMailbox.stopRunner as CFString, nil, .deliverImmediately)
        CFNotificationCenterAddObserver(center, observer, { _, observer, _, _, _ in
            guard let observer else { return }
            let model = Unmanaged<AppModel>.fromOpaque(observer).takeUnretainedValue()
            Task { @MainActor in model.handoffDone() }
        }, ApprovalMailbox.handoffDone as CFString, nil, .deliverImmediately)
    }

    /// The person tapped "Done, carry on" on the Live Activity's "Your turn" card.
    func handoffDone() {
        guard let id = ApprovalMailbox.drainHandoffDone() else { return }
        log.add("handoff", "done by the owner: \(id)")
        if id == Self.runnerPasscodeHandoff {
            // The runner's own launch: the launcher notices by itself when the runner answers.
            activity.update { $0.handoff = nil; $0.phase = runner.isRunning ? .idle : .working; $0.headline = runner.isRunning ? "Ready for the agent" : "Starting the runner" }
        } else {
            activity.update { $0.handoff = nil; $0.phase = .working; $0.headline = "Carrying on" }
            core.handoffDone(id: id)
        }
    }
    static let runnerPasscodeHandoff = "runner-passcode"

    /// What the owner is asked to do, when the model gave no words of its own.
    static func handoffWording(_ kind: PokiActivityAttributes.Handoff.Kind) -> String {
        switch kind {
        case .runnerPasscode: "The phone asks for your passcode so the runner can start"
        case .passcode: "The screen asks for your passcode"
        case .password: "The screen asks for a password"
        case .verification: "The screen asks for a verification step"
        case .payment: "The screen asks you to confirm a payment"
        case .other: "The agent cannot act on this screen; please do this step"
        }
    }

    /// Decisions an intent left in the App Group mailbox because it ran outside the app.
    func drainApprovals() {
        for decision in ApprovalMailbox.drain() { decide(decision) }
    }

    /// A decision from the Live Activity. The card shows the answer at once (Allowing, Denying).
    /// Allow is tapped on the expanded Dynamic Island, which takes about a second to collapse; input
    /// sent at once can land on it (iOS then opens Poki). So the Live Activity's decisions reach
    /// PokiCore after a short pause, the app's own buttons at once.
    func decide(_ decision: ApprovalDecision) {
        // A tap on an approval that already ended (answered in the app, or timed out) does nothing.
        guard approvals.contains(where: { $0.id == decision.approvalID }) else { return }
        log.add("approval", "\(decision.approved ? "allowed" : "denied") \(decision.approvalID) on the Live Activity")
        activity.update { state in
            guard state.approval?.id == decision.approvalID else { return }
            state.phase = .deciding
            state.decision = decision.approved
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.islandCollapse))
            core.resolveApproval(id: decision.approvalID, approved: decision.approved)
        }
    }

    /// How long the expanded island takes to fold after a tap on its button.
    static let islandCollapse: TimeInterval = 1.5

    /// The launcher's fix as the Live Activity's content line, in English (the face words it in the
    /// system's language). The fixes the launcher sends (native/launcher/src/device.rs, launch.rs) have
    /// names of a few words; any other text gives its first part. What to do is in the app, which shows
    /// the whole fix.
    nonisolated static func problemText(_ fix: String) -> String {
        let short: [(String, String)] = [
            ("Turn on the loopback", "Loopback Off"),
            ("Poki needs the internet", "No Internet"),
            ("Mounting the developer disk image timed out", "No Internet"),
            ("This iOS version needs a newer", "Disk Image Outdated"),
            ("The developer disk image did not install", "Fetching Disk Image"),
            ("Pair again", "Pairing Refused"),
            ("Turn on Developer Mode", "Developer Mode Off"),
            ("Install Poki Runner", "Poki Runner Missing"),
        ]
        return short.first { fix.hasPrefix($0.0) }?.1 ?? firstPart(fix)
    }

    /// A text up to its first colon or the end of its first sentence, capitalised.
    nonisolated static func firstPart(_ text: String) -> String {
        let mark = [": ", ". "].compactMap { text.range(of: $0) }.min { $0.lowerBound < $1.lowerBound }
        let part = mark.map { String(text[..<$0.lowerBound]) } ?? text
        return part.prefix(1).uppercased() + part.dropFirst()
    }

    // MARK: Pairing

    func importPairingFile(from url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        // A lockdown pairing plist or an RPPairing file; both are property lists.
        _ = try PropertyListSerialization.propertyList(from: data, format: nil)
        try data.write(to: AppFiles.pairingFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        setup.pairingFile = AppFiles.pairingFile.path
        pairingTrouble = nil; pairingVerifiedAt = nil
        log.add("pairing", "pairing file imported")
    }

    func startPairing() {
        guard loopback.isWorking else {
            pairing = .failed("Enable a local connection in Setup and wait for the connection check to pass, then try pairing again.")
            return
        }
        pairing = .advertising
        // Started now, while Poki is in front: the PIN arrives while the person is in Settings, when
        // iOS no longer lets Poki start a Live Activity.
        activity.start(deviceName: deviceName)
        activity.update { $0.phase = .pairing; $0.pin = nil; $0.headline = "Pair in Settings" }
        // The person completes pairing in Settings. Keep the listener and Bonjour publication alive
        // there, before a regular Poki session can be started. Without it (audio can be busy, as in a
        // call) pairing still starts, as it did before the keep-alive.
        do { try pairingKeepAlive.start() }
        catch { log.add("pairing", "keep-alive did not start (\(error.localizedDescription)); iOS may stop the pairing while Settings is open") }
        do {
            try pairer.start(hostName: "Poki", saveTo: AppFiles.pairingFile) { [weak self] event in
                Task { @MainActor in self?.pairingChanged(event) }
            }
        } catch { pairingChanged(.failed("\(error)")) }
    }

    func cancelPairing() {
        pairer.cancel()
        pairingKeepAlive.stop()
        pairing = nil
        activity.update { $0.pin = nil }
        if !sessionOn { stopGuide(); activity.end() }
    }

    /// Waiting for Settings or showing a PIN: the listener, Bonjour and the keep-alive are running.
    var pairingUnderWay: Bool {
        switch pairing {
        case .advertising?, .pin?: true
        default: false
        }
    }

    /// The person left the pairing step in Poki (another tab, or another step): the pairing stops at
    /// once, and with it the background keep-alive. Going to Settings is not leaving.
    func leftPairing() {
        guard pairingUnderWay else { return }
        log.add("pairing", "cancelled: the pairing step was left")
        cancelPairing()
    }

    private func pairingChanged(_ event: PairingEvent) {
        pairing = event
        switch event {
        case .pin(let pin):
            // The PIN goes in the Live Activity, so it is visible while the user is in Settings.
            activity.start(deviceName: deviceName)
            activity.update { $0.phase = .pairing; $0.pin = pin; $0.headline = "Pairing code" }
        case .paired(let url):
            pairingKeepAlive.stop()
            try? (url as NSURL).setResourceValue(URLFileProtection.completeUntilFirstUserAuthentication, forKey: .fileProtectionKey)
            setup.pairingFile = url.path
            pairingTrouble = nil; pairingVerifiedAt = nil
            log.add("pairing", "paired on the phone")
            activity.update { $0.phase = .idle; $0.pin = nil; $0.headline = "Paired" }
            if !sessionOn { Task { try? await Task.sleep(for: .seconds(4)); if !self.sessionOn { self.activity.end() } } }
        case .failed(let why):
            pairingKeepAlive.stop()
            activity.update { $0.phase = .problem; $0.pin = nil; $0.label = "Pairing Failed"; $0.headline = Self.firstPart(why) }
            if !sessionOn { Task { try? await Task.sleep(for: .seconds(8)); if !self.sessionOn { self.activity.end() } } }
        case .advertising: break
        }
    }

    // MARK: Setup guide

    /// The person is going to Settings for a setup step: the Live Activity shows the step and what to
    /// tap, so it stays in view there. Ended when they come back and the step is done.
    func guide(_ step: SetupStep) {
        guiding = step
        guard !sessionOn else { return }
        activity.start(deviceName: deviceName)
        let steps = SetupStep.shown
        activity.update {
            $0.phase = .setup
            $0.headline = "Setting up Poki"
            $0.guide = .init(number: (steps.firstIndex(of: step) ?? 0) + 1, count: steps.count, title: step.activityTitle)
        }
    }

    func stopGuide() {
        guard guiding != nil else { return }
        guiding = nil
        activity.update { $0.guide = nil }
        if !sessionOn, activity.state.phase == .setup { activity.end() }
    }

    func isDone(_ step: SetupStep) -> Bool {
        switch step {
        case .runner: setup.runnerInstalled
        case .developerMode: setup.developerMode
        case .loopback: setup.loopback != .none && loopback.isWorking
        case .pairing: pairingPath != nil && pairingTrouble == nil && diskImage.isReady
        case .automation: setup.uiAutomation
        case .background: background.allowed && activity.enabled
        }
    }

    var setupComplete: Bool { SetupStep.shown.allSatisfy(isDone) }

    var activityProblem: String? { activity.lastError }
    var activitiesEnabled: Bool { activity.enabled }

    // MARK: Relay and connectors

    static let noRelay = "Enter your relay's address first (Settings › Relay). Poki has no default relay."

    /// Saves the relay address the person entered; false when it is not one. A running session moves
    /// to the new relay at once.
    func setRelay(_ text: String) -> Bool {
        guard let address = RelayAddress(text) else { return false }
        guard address != relayAddress else { return true }
        RelayAddress.saved = address
        relayAddress = address
        log.add("relay", "address set to \(address.origin.host() ?? "?")")
        if problem == Self.noRelay { problem = nil }
        if sessionOn {
            core.stop()
            core.start(relay: address)
        }
        return true
    }

    /// The MCP address for a connector, on the person's relay; nil until a relay is set.
    func connectorURL(for secret: ConnectorSecret) -> URL? {
        relayAddress.map { identity.url(for: secret, relay: $0) }
    }

    func addConnector(name: String) -> ConnectorSecret {
        let secret = identity.addSecret(name: name)
        accessChanged()
        return secret
    }
    func revoke(_ secret: ConnectorSecret) { identity.revoke(secret); accessChanged() }
    private func accessChanged() {
        host.update(key: identity.signingKey, hashes: identity.accessHashes)
        core.accessChanged()
    }
}

/// Whether WebDriverAgent answers /status right now (2 s at most).
enum RunnerProbe {
    /// Asks the runner to shut itself down: it ends its test and exits, which takes the automation
    /// banner with it. Nothing happens when it is not running.
    static func shutdown() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        let session = URLSession(configuration: configuration)
        func send(_ method: String, _ path: String) async -> Data? {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:8100\(path)")!, timeoutInterval: 2)
            request.httpMethod = method
            return try? await session.data(for: request).0
        }
        // The shutdown request waits in WDA's queue behind a slow tree read; ending the session first
        // voids whatever is queued, so the shutdown is handled at once.
        if let status = await send("GET", "/status"),
           let json = try? JSONSerialization.jsonObject(with: status) as? [String: Any],
           let id = json["sessionId"] as? String, !id.isEmpty {
            _ = await send("DELETE", "/session/\(id)")
        }
        _ = await send("GET", "/wda/shutdown")
    }

    static func answers() async -> Bool {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:8100/status")!, timeoutInterval: 2)
        request.httpMethod = "GET"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        guard let (_, response) = try? await URLSession(configuration: configuration).data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}
