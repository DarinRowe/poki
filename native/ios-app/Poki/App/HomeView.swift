import SwiftUI

/// Home, after ESP-139 board 01. Three faces on the blue page:
/// - first run (A): what Poki does, the two things to set up, one button into setup;
/// - at work (B): the approval on top, the latest screen beside the current step, Stop, the
///   connection summary and All Steps;
/// - standing by (C): a big word for the real state, the Poki switch with the relay, the runner, the
///   loopback and anything in the way, and the last run.
/// The runner's settings moved to Settings (the gear).
struct HomeView: View {
    @Environment(AppModel.self) private var model
    var openSetup: () -> Void
    var openSettings: () -> Void

    var body: some View {
        SitePage {
            ScrollView {
                Group {
                    if model.pairingPath == nil && !model.sessionOn {
                        FirstRun(openSetup: openSetup, openSettings: openSettings)
                    } else if Self.atWork(model) {
                        AtWork(openSetup: openSetup, openSettings: openSettings)
                    } else {
                        StandingBy(openSetup: openSetup, openSettings: openSettings)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: HomeRoute.self) { route in
            switch route {
            case .steps: AllStepsView()
            case .status: StatusView(openSetup: openSetup)
            }
        }
        .animation(.snappy, value: model.sessionOn)
        .animation(.snappy, value: model.approvals.count)
        .animation(.snappy, value: model.runnerPaused)
    }

    /// The agent is at it: the runner is awake and has done something, or an approval waits.
    static func atWork(_ model: AppModel) -> Bool {
        model.sessionOn && (!model.approvals.isEmpty || !model.runnerPaused && (model.activityText != "Idle" || !model.recentSteps.isEmpty))
    }
}

enum HomeRoute: Hashable { case steps, status }

// MARK: A, first run

private struct FirstRun: View {
    @Environment(AppModel.self) private var model
    var openSetup: () -> Void
    var openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) { Spacer(); VoiceButton(); GearButton(action: openSettings) }
                .frame(height: 52).padding(.horizontal, 16)
            VStack(alignment: .leading, spacing: 20) {
                BearAvatar(size: 96)
                Text("Your agents can use this iPhone.").site(36, .heavy, line: 40, tracking: -0.02)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Claude, Codex, and other MCP clients tap and type for you. You see every step and approve anything sensitive.")
                    .site(17, line: 24).foregroundStyle(Site.c3).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28).padding(.top, 36)

            VStack(spacing: 0) {
                Button(action: openSetup) {
                    PlanRow(number: 1, title: Text("Set Up This iPhone"), detail: Text("No computer required."), value: setupValue)
                }
                .buttonStyle(.plain)
                Site.edge.frame(height: 1)
                Button(action: openSettings) {
                    PlanRow(number: 2, title: Text("Add your agent"), detail: nil, value: Text("1 link"))
                }
                .buttonStyle(.plain)
            }
            .glassCard()
            .padding(.horizontal, 16).padding(.top, 32)

            IssueCards(openSetup: openSetup).padding(.top, 12)

            Spacer(minLength: 32)
            VStack(spacing: 14) {
                CapsuleButton(title: "Set Up Poki", action: openSetup)
                Text("About 5 minutes. Everything stays on this iPhone.").site(13, line: 16).foregroundStyle(Site.c4)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16).padding(.bottom, 10)
        }
        .containerRelativeFrame(.vertical, alignment: .top) { height, _ in height }
    }

    private var setupValue: Text {
        let done = SetupStep.allCases.filter(model.isDone).count
        let total = SetupStep.allCases.count
        return done == 0 ? Text(String(localized: "setup-steps", defaultValue: "\(total) steps")) : Text("\(done) of \(total)")
    }
}

private struct PlanRow: View {
    var number: Int
    var title: Text
    var detail: Text?
    var value: Text
    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: "\(number)").site(14, .semibold, line: 18)
                .frame(width: 28, height: 28).background(Site.glass2, in: .circle)
            VStack(alignment: .leading, spacing: 0) {
                title.site(17, line: 22)
                if let detail { detail.site(13, line: 18).foregroundStyle(Site.c3) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            value.site(15, line: 18).foregroundStyle(Site.c4)
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
        .contentShape(.rect)
    }
}

// MARK: B, at work

private struct AtWork: View {
    @Environment(AppModel.self) private var model
    var openSetup: () -> Void
    var openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                BearAvatar(size: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "Poki").site(17, .semibold, line: 22)
                    HStack(spacing: 4) {
                        Text(verbatim: "●").foregroundStyle(Health.relay(model).color)
                        Text(Health.relay(model).word)
                    }
                    .site(12, line: 16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                PokiSwitch()
                VoiceButton()
                GearButton(action: openSettings)
            }
            .frame(height: 52).padding(.horizontal, 16)

            VStack(spacing: 12) {
                ForEach(model.approvals, id: \.id) { ApprovalCard(approval: $0) }
            }
            .padding(.horizontal, 16).padding(.top, 12)

            NowSection().padding(.horizontal, 16).padding(.top, 20)

            VStack(spacing: 8) {
                NavigationLink(value: HomeRoute.status) { SummaryRow() }.buttonStyle(.plain)
                NavigationLink(value: HomeRoute.steps) {
                    HStack {
                        Text("All Steps").site(15, line: 18)
                        Spacer()
                        Text(Self.stepCount(model)).site(15, line: 18).foregroundStyle(Site.c4)
                        Text(verbatim: "›").site(15, line: 18).foregroundStyle(Site.c4)
                    }
                    .padding(.horizontal, 16).frame(height: 44).glassCard(14).contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.top, 22)

            IssueCards(openSetup: openSetup).padding(.top, 12)
            Spacer(minLength: 24)
        }
    }

    /// "5 steps, 1 missed", counting the step under way.
    @MainActor static func stepCount(_ model: AppModel) -> String {
        let steps = model.recentSteps
        let missed = steps.filter { !$0.ok }.count
        let count = String(localized: "\(steps.count + (model.activityText != "Idle" ? 1 : 0)) steps")
        return missed == 0 ? count : String(localized: "\(count), \(missed) missed")
    }
}

/// The approval, on a white card that floats above the blue.
struct ApprovalCard: View {
    @Environment(AppModel.self) private var model
    var approval: PendingApproval
    /// PokiCore's approvals last 30 s.
    private static let window: TimeInterval = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Approval Required").site(15, .semibold, line: 18)
                Spacer()
                Text(timerInterval: Date()...max(Date(), approval.expires), countsDown: true)
                    .mono(13, .semibold).monospacedDigit().foregroundStyle(Site.ink)
                    .padding(.horizontal, 9).frame(height: 24).background(Site.tint, in: .capsule)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(approval.summary).site(22, .bold, line: 28, tracking: -0.01).fixedSize(horizontal: false, vertical: true)
                Text(Self.reasonLine(approval)).site(15, line: 22, tracking: -0.01).foregroundStyle(Site.text2)
            }
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let left = max(0, approval.expires.timeIntervalSince(context.date)) / Self.window
                GeometryReader { geo in
                    Capsule().fill(Site.tint)
                        .overlay(alignment: .leading) { Capsule().fill(Site.blue).frame(width: geo.size.width * min(1, left)) }
                }
                .frame(height: 3)
            }
            .accessibilityHidden(true)
            HStack(spacing: 10) {
                Button { model.resolve(approval, approved: false) } label: {
                    Text("Don’t Allow").site(17, .semibold, line: 22).foregroundStyle(Site.text)
                        .frame(width: 128, height: 46).background(Site.tint, in: .capsule)
                }
                Button { model.resolve(approval, approved: true) } label: {
                    Text("Allow").site(17, .semibold, line: 22).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 46).background(Site.blue, in: .capsule)
                }
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Site.text)
        .padding(16)
        .background(Color.white, in: .rect(cornerRadius: 22, style: .continuous))
        .shadow(color: Color(hex: 0x002878).opacity(0.35), radius: 20, y: 18)
    }

    /// "Sending a message in Messages", from PokiCore's reason.
    static func reasonLine(_ approval: PendingApproval) -> String {
        var phrase = approval.reason
        if let quote = phrase.range(of: " (\"") { phrase = String(phrase[..<quote.lowerBound]) }
        phrase = Bundle.main.localizedString(forKey: phrase, value: phrase, table: nil)
        let line = approval.app.isEmpty || phrase.contains(" in ") ? phrase : String(localized: "\(phrase) in \(approval.app)")
        return line.prefix(1).uppercased() + line.dropFirst()
    }
}

/// What the agent is doing: the latest screen beside the step, the last three steps and Stop.
private struct NowSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ScreenThumbnail(version: model.recentSteps.count)
            VStack(alignment: .leading, spacing: 6) {
                Text(label).site(13, .semibold, line: 16)
                Text(headline).site(24, .heavy, line: 28, tracking: -0.02).lineLimit(3).contentTransition(.opacity)
                Text(place).site(13, line: 16).foregroundStyle(Site.c3)
                Site.edge.frame(height: 1)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.recentSteps.suffix(3)) { step in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(verbatim: step.ok ? "✓" : "✕").foregroundStyle(step.ok ? Color.white : Site.bad).frame(width: 12, alignment: .leading)
                            Text(ActivityWords.label(step.text)).foregroundStyle(Site.c3).lineLimit(1)
                        }
                        .site(13, line: 17)
                    }
                }
                .padding(.top, 8)
                Spacer(minLength: 12)
                Button(role: .destructive) { model.pauseRunner() } label: {
                    HStack(spacing: 6) { Text(verbatim: "■"); Text("Stop") }
                        .site(15, .semibold, line: 18).foregroundStyle(stopEnabled ? Color.white : Site.c4)
                        .padding(.horizontal, 16).frame(height: 36).background(Site.glass2, in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(!stopEnabled)
                .opacity(stopEnabled ? 1 : 0.5)
            }
            .frame(maxWidth: .infinity, minHeight: 286, alignment: .topLeading)
        }
    }

    private var stopEnabled: Bool { model.approvals.isEmpty && !model.runnerPaused }
    private var working: Bool { model.activityText != "Idle" }
    private var label: LocalizedStringKey { !model.approvals.isEmpty ? "Paused for you" : working ? "Working" : "Last step" }
    private var headline: String { (working ? model.activityText : model.recentSteps.last?.text).map(ActivityWords.label) ?? String(localized: "Waiting for the agent") }
    private var place: String {
        let step = model.recentSteps.count + (working ? 1 : 0)
        guard let app = model.currentApp else { return String(localized: "Step \(step)") }
        return String(localized: "\(app), Step \(step)")
    }
}

/// The latest screen the agent saw, drawn like a small phone.
private struct ScreenThumbnail: View {
    var version: Int
    var body: some View {
        if let image = (SharedContainer.thumbnailURL.flatMap { UIImage(contentsOfFile: $0.path) }) ?? Thumbnail.previewImage {
            Image(uiImage: image).resizable().scaledToFill()
                .frame(width: 132, height: 286)
                .background(.white)
                .clipShape(.rect(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Site.edge, lineWidth: 1.5))
                .id(version)
                .accessibilityLabel(Text("The latest screen"))
        }
    }
}

/// Relay, runner and loopback in one line; opens their details.
private struct SummaryRow: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack {
            item(Health.relay(model).color, "Relay")
            Spacer()
            item(Health.runner(model).color, "Runner")
            Spacer()
            item(Health.loopback(model).color, "Loopback")
            Spacer()
            Text(verbatim: "›").site(15, line: 18).foregroundStyle(Site.c4)
        }
        .padding(.horizontal, 16).frame(height: 44).glassCard(14).contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private func item(_ color: Color, _ name: LocalizedStringKey) -> some View {
        HStack(spacing: 6) { StatusDot(color: color); Text(name).site(14, line: 18) }
    }
}

/// The Poki switch: turns the whole session on and off.
private struct PokiSwitch: View {
    @Environment(AppModel.self) private var model
    var label: LocalizedStringKey?
    var body: some View {
        Toggle(isOn: Binding(get: { model.sessionOn }, set: { $0 ? model.startSession() : model.stopSession() })) {
            if let label { Text(label).site(17, line: 22).frame(maxWidth: .infinity, alignment: .leading) }
        }
        .toggleStyle(SiteToggleStyle())
        .accessibilityLabel(Text(verbatim: "Poki"))
    }
}

// MARK: C, standing by

private struct StandingBy: View {
    @Environment(AppModel.self) private var model
    var openSetup: () -> Void
    var openSettings: () -> Void

    var body: some View {
        let issues = Issue.current(model)
        VStack(spacing: 0) {
            HStack(spacing: 8) { Spacer(); VoiceButton(); GearButton(action: openSettings) }
                .frame(height: 52).padding(.horizontal, 16)
            VStack(alignment: .leading, spacing: 14) {
                BearAvatar(size: 74).padding(4)
                    .overlay(Circle().strokeBorder(.white, style: StrokeStyle(lineWidth: 3, dash: issues.isEmpty && model.sessionOn ? [] : [6, 4])))
                Text(title(issues)).site(40, .heavy, line: 44, tracking: -0.02).fixedSize(horizontal: false, vertical: true)
                Text(subtitle(issues)).site(17, line: 23).foregroundStyle(Site.c3).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 8)

            HealthCard(issues: issues, openSetup: openSetup).padding(.horizontal, 16).padding(.top, 24)

            // Setup is always one tap away, on or off (ESP-168: with Poki off there was no way back
            // into it from Home; the board does not draw this row).
            Button(action: openSetup) {
                let done = SetupStep.allCases.filter(model.isDone).count
                let total = SetupStep.allCases.count
                HStack {
                    Text("Setup").site(15, line: 18)
                    Spacer(minLength: 8)
                    Text("\(done) of \(total)").site(15, line: 18).foregroundStyle(done == total ? Site.ok : Site.c4).monospacedDigit()
                    Text(verbatim: "›").site(15, line: 18).foregroundStyle(Site.c4)
                }
                .padding(.horizontal, 16).frame(height: 44).glassCard(14).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16).padding(.top, 16)

            if let last = model.recentSteps.last {
                NavigationLink(value: HomeRoute.steps) {
                    HStack {
                        HStack(spacing: 4) {
                            Text(verbatim: last.ok ? "✓" : "✕").foregroundStyle(last.ok ? Site.ok : Site.bad)
                            model.currentApp.map { Text("Finished in \($0)") } ?? Text("Finished")
                        }
                        .site(15, line: 18).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(runSummary).site(15, line: 18).foregroundStyle(Site.c4)
                        Text(verbatim: "›").site(15, line: 18).foregroundStyle(Site.c4)
                    }
                    .padding(.horizontal, 16).frame(height: 44).glassCard(14).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16).padding(.top, 10)
            }
            Spacer(minLength: 24)
        }
    }

    private func title(_ issues: [Issue]) -> LocalizedStringKey {
        !model.sessionOn ? "Poki Is Off" : issues.isEmpty ? "Ready" : "Almost Ready"
    }

    private func subtitle(_ issues: [Issue]) -> LocalizedStringKey {
        if !model.sessionOn { return "Turn on so your agents can use this iPhone." }
        if issues.contains(where: { $0.id == "loopback" }), case .ready = model.relayStatus {
            return "Agents can reach this iPhone, but Poki can’t tap until Loopback is on."
        }
        if !issues.isEmpty { return "Fix the item below so your agents can use this iPhone." }
        return model.runnerPaused ? "The runner starts when an agent asks." : "Ready for the agent’s next step."
    }

    /// "12 steps in 1:24", from the first to the last of the recent steps.
    private var runSummary: String {
        let steps = model.recentSteps
        guard let first = steps.first, let last = steps.last else { return "" }
        let seconds = Int(last.at.timeIntervalSince(first.at))
        let time = String(format: "%d:%02d", seconds / 60, seconds % 60)
        return String(localized: "\(steps.count) steps in \(time)")
    }
}

/// The Poki switch, the relay, the runner and the loopback, with anything in the way under them.
struct HealthCard: View {
    @Environment(AppModel.self) private var model
    var issues: [Issue]
    var openSetup: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PokiSwitch(label: "Poki").padding(.horizontal, 16).frame(height: 48)
                .overlay(alignment: .bottom) { Site.edge.frame(height: 1) }
            row("Relay", Health.relay(model))
            row("Runner", Health.runner(model), divider: !issues.isEmpty || !hideLoopback)
            if !hideLoopback { row("Loopback", Health.loopback(model), divider: !issues.isEmpty) }
            ForEach(Array(issues.enumerated()), id: \.element.id) { i, issue in
                IssueSection(issue: issue, openSetup: openSetup)
                    .overlay(alignment: .bottom) { if i < issues.count - 1 { Site.edge.frame(height: 0.5) } }
            }
        }
        .glassCard(14)
    }

    /// The loopback issue already says it is off.
    private var hideLoopback: Bool { issues.contains { $0.id == "loopback" } }

    private func row(_ title: LocalizedStringKey, _ health: Health, divider: Bool = true) -> some View {
        HStack {
            Text(title).site(17, line: 22)
            Spacer()
            HStack(spacing: 4) { Text(verbatim: "●").foregroundStyle(health.color); Text(health.word) }
                .site(17, line: 22).foregroundStyle(Site.c3)
        }
        .padding(.horizontal, 16).frame(height: 44)
        .overlay(alignment: .bottom) { if divider { Site.edge.frame(height: 1) } }
        .accessibilityElement(children: .combine)
    }
}

/// A status word and the colour of its dot.
struct Health {
    var word: String
    var color: Color
    static let off = Color.white.opacity(0.48)

    @MainActor static func relay(_ model: AppModel) -> Health {
        switch model.relayStatus {
        case .ready: Health(word: String(localized: "Online"), color: Site.ok)
        case .connecting: Health(word: String(localized: "Connecting"), color: .white)
        case .offline: Health(word: String(localized: "Offline"), color: Site.bad)
        case .off: Health(word: String(localized: "Off"), color: off)
        }
    }

    @MainActor static func runner(_ model: AppModel) -> Health {
        guard model.sessionOn else { return Health(word: String(localized: "Off"), color: off) }
        let runner = model.runner
        let word = Bundle.main.localizedString(forKey: runner.title, value: runner.title, table: nil)
        if runner.isRunning { return Health(word: word, color: Site.ok) }
        if runner.state == "failed" { return Health(word: word, color: Site.bad) }
        return Health(word: word, color: model.runnerPaused ? off : .white)
    }

    @MainActor static func loopback(_ model: AppModel) -> Health {
        let monitor = model.loopback
        switch monitor.state {
        case .working: return Health(word: String(localized: "On"), color: Site.ok)
        case .checking: return Health(word: String(localized: "Checking…"), color: .white)
        case .noAnswer: return Health(word: String(localized: "No Answer"), color: Site.bad)
        case .off: return Health(word: String(localized: "Off"), color: Site.bad)
        }
    }
}

/// One thing in the way, inside the health card: the red dot and title, what to do, the fix.
private struct IssueSection: View {
    @Environment(AppModel.self) private var model
    var issue: Issue
    var openSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) { Text(verbatim: "●").foregroundStyle(Site.bad); Text(issue.title) }
                .site(15, .semibold, line: 18)
            Text(issue.text).site(15, line: 20).foregroundStyle(Site.c3).fixedSize(horizontal: false, vertical: true)
            if let button = issue.button {
                Button { issue.act(model, openSetup: openSetup) } label: { Text(button).site(15, .semibold, line: 18) }
                    .buttonStyle(.plain).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12).padding(.horizontal, 16)
    }
}

/// Issues outside the health card (first run, at work): each in its own glass card.
struct IssueCards: View {
    @Environment(AppModel.self) private var model
    var openSetup: () -> Void
    var body: some View {
        let issues = Issue.current(model)
        if !issues.isEmpty {
            VStack(spacing: 8) {
                ForEach(issues) { IssueSection(issue: $0, openSetup: openSetup).glassCard(14) }
            }
            .padding(.horizontal, 16)
        }
    }
}

/// Something that keeps agents from using the phone, with the one thing the person has to do.
struct Issue: Identifiable {
    enum Fix { case setup, settings, retry, none }
    var id: String
    var title: String
    var text: String
    var fix: Fix

    var button: LocalizedStringKey? {
        switch fix {
        case .setup: "Open Setup"
        case .settings: "Open Settings"
        case .retry: "Try Again"
        case .none: nil
        }
    }

    @MainActor func act(_ model: AppModel, openSetup: () -> Void) {
        switch fix {
        case .setup: openSetup()
        case .settings: if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        case .retry: model.runnerPaused ? model.wakeRunner() : model.restartRunner()
        case .none: break
        }
    }

    /// Text from PokiCore and the launcher stays as it came; Poki's own sentences are localized.
    private static func local(_ text: String) -> String { Bundle.main.localizedString(forKey: text, value: text, table: nil) }

    @MainActor static func current(_ model: AppModel) -> [Issue] {
        var out: [Issue] = []
        if model.sessionOn {
            let runner = model.runner
            if runner.state == "failed", model.pairingTrouble == nil {
                let fix = runner.fix ?? ""
                let kind: Fix = fix.contains("Install Poki Runner") || fix.contains("Pair again") || fix.contains("setup") ? .setup : fix.contains("Developer Mode") ? .settings : .retry
                out.append(Issue(id: "runner", title: String(localized: "The runner stopped"),
                                 text: fix.isEmpty ? (runner.detail.map { "\($0.prefix(1).uppercased())\($0.dropFirst())." } ?? String(localized: "Poki starts it again on the next agent request.")) : local(fix), fix: kind))
            } else if runner.state == "waiting_network", let fix = runner.fix, fix.contains("internet") {
                out.append(Issue(id: "network", title: String(localized: "Waiting for the internet"), text: local(fix), fix: .none))
            } else if runner.state == "waiting_network" || !model.loopback.isWorking && model.loopback.state != .checking {
                out.append(Issue(id: "loopback", title: String(localized: "Loopback is off"),
                                 text: String(localized: "Turn on your proxy app with the Poki module, or connect LocalDevVPN."), fix: .setup))
            }
            if let trouble = model.pairingTrouble {
                out.append(Issue(id: "pairing", title: String(localized: "Pair this iPhone again"),
                                 text: String(localized: "The phone no longer accepts Poki’s pairing (\(trouble)). Pair again in Setup; it takes a minute."), fix: .setup))
            }
            if model.passcodeHint {
                out.append(Issue(id: "passcode", title: String(localized: "Enter the passcode if the iPhone asks"),
                                 text: String(localized: "iOS asks for the passcode before UI Automation after Poki Runner was force-closed or the iPhone restarted. Enter it once; Poki carries on by itself."), fix: .none))
            }
            if case .offline = model.relayStatus {
                out.append(Issue(id: "relay", title: String(localized: "Agents can’t reach this iPhone"),
                                 text: String(localized: "Poki is offline. Check that the phone has internet; Poki reconnects by itself."), fix: .none))
            }
            if model.background.denied {
                out.append(Issue(id: "location", title: String(localized: "Poki can’t stay on in the background"),
                                 text: String(localized: "Allow location access for Poki (Settings › Poki › Location › Always). Poki uses it only to keep running; it never records where you are."), fix: .settings))
            }
        }
        if let problem = model.problem {
            out.append(Issue(id: "problem", title: String(localized: "Needs attention"), text: local(problem), fix: problem.contains("Pair") || problem.contains("disk image") ? .setup : .none))
        }
        if let problem = model.activityProblem {
            out.append(Issue(id: "activity", title: String(localized: "Live Activity is off"), text: local(problem), fix: .settings))
        }
        return out
    }
}

/// Relay, runner and loopback in full, from the summary row on Home (the board says "tap for details"
/// and does not draw the page: it is the standing-by health card on its own).
private struct StatusView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var openSetup: () -> Void
    var body: some View {
        SitePage {
            VStack(spacing: 0) {
                SheetHeader(title: Text("Status"), back: "Poki", sideWidth: 70, onBack: { dismiss() })
                ScrollView {
                    HealthCard(issues: Issue.current(model), openSetup: openSetup).padding(.horizontal, 16).padding(.top, 12)
                    GroupFootnote(text: LocalizedStringKey(model.loopback.detail))
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: D, all steps

/// Every recent step, newest first, on a white card (board 01, D).
struct AllStepsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SitePage {
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: { HStack(spacing: 4) { Text(verbatim: "‹"); Text(verbatim: "Poki") }.site(17, line: 22) }
                        .buttonStyle(.plain).frame(width: 52, alignment: .leading)
                    Spacer()
                    Text("All Steps").site(17, .semibold, line: 22)
                    Spacer()
                    Color.clear.frame(width: 52, height: 1)
                }
                .frame(height: 44).padding(.horizontal, 16)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.currentApp ?? String(localized: "All Steps")).site(28, .heavy, line: 34, tracking: -0.02)
                        if let first = model.recentSteps.first {
                            Text("\(AtWork.stepCount(model)). Started at \(first.at.formatted(date: .omitted, time: .shortened)).")
                                .site(15, line: 20).foregroundStyle(Site.c3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)

                    Group {
                        if rows.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "clock").font(.system(size: 16)).foregroundStyle(Site.text3)
                                Text("Steps from your agent appear here and on the Lock Screen.").site(15, line: 20)
                                    .foregroundStyle(Site.text2).multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 28).padding(.horizontal, 16)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                                    StepRow(row: row, last: i == rows.count - 1)
                                }
                            }
                            .padding(16)
                        }
                    }
                    .whiteCard()
                    .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 24)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    struct Row {
        var text: String
        var detail: String
        var failed: Bool
        var at: Date
    }

    /// The step under way (waiting for approval or working) first, then the finished ones.
    private var rows: [Row] {
        var out: [Row] = []
        if model.activityText != "Idle" {
            out.append(Row(text: model.activityText, detail: model.approvals.isEmpty ? String(localized: "Working") : String(localized: "Waiting for Approval"),
                           failed: false, at: Date()))
        }
        for step in model.recentSteps.reversed() {
            let failure = step.failure.map { Bundle.main.localizedString(forKey: $0, value: $0, table: nil) }.map { $0.prefix(1).uppercased() + $0.dropFirst() }
            out.append(Row(text: step.text, detail: failure ?? step.app ?? String(localized: "Done"), failed: !step.ok, at: step.at))
        }
        return out
    }
}

private struct StepRow: View {
    var row: AllStepsView.Row
    var last: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Image(systemName: row.failed ? "xmark" : Self.symbol(for: row.text))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(row.failed ? Site.bad : Site.blue)
                    .frame(width: 30, height: 30)
                    .background(row.failed ? Color(hex: 0xFFECEB) : Site.tint, in: .circle)
                if !last { Site.hair.frame(width: 1.5).frame(maxHeight: .infinity) }
            }
            .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ActivityWords.label(row.text)).site(15, .medium, line: 20).foregroundStyle(Site.text).lineLimit(2)
                    Spacer(minLength: 8)
                    Text(row.at, style: .time).site(12, line: 16).monospacedDigit().foregroundStyle(Site.text3)
                }
                Text(row.detail).site(13, line: 18).foregroundStyle(row.failed ? Site.text : Site.text2).lineLimit(2)
            }
            .padding(.bottom, last ? 0 : 16)
        }
    }

    static func symbol(for text: String) -> String {
        let verb = text.split(separator: " ").first.map(String.init) ?? ""
        switch verb {
        case "Tap": return "hand.tap"
        case "Press": return text.hasSuffix("button") ? "button.horizontal.top.press" : "keyboard"
        case "Type": return "character.cursor.ibeam"
        case "Swipe", "Scroll": return "hand.draw"
        case "Drag": return "hand.point.up.left"
        case "Zoom": return "arrow.up.left.and.arrow.down.right"
        case "Open": return "app.badge"
        case "Look": return "eye"
        case "Wait": return "hourglass"
        default: return "sparkles"
        }
    }
}
