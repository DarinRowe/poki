import SwiftUI
import UniformTypeIdentifiers

/// Setup, one step per page (ESP-139 board 03). Steps the phone can check by itself (the loopback,
/// pairing, location and Live Activities) move on when they pass; steps it can't (Poki Runner,
/// Developer Mode, UI Automation) keep a switch the person turns on, and Continue lights up after it.
/// Steps that send the person to Settings put the step and what to tap in the Live Activity.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var index: Int
    private let steps = SetupStep.shown

    init(start: Int) { _index = State(initialValue: start) }

    /// The first step not done, where setup opens.
    @MainActor static func firstOpen(_ model: AppModel) -> Int {
        SetupStep.shown.firstIndex { !model.isDone($0) } ?? 0
    }

    private var step: SetupStep { steps[index] }

    var body: some View {
        SitePage {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(step.pageTitle).site(30, .heavy, line: 36, tracking: -0.02).fixedSize(horizontal: false, vertical: true)
                            Text(step.pageSummary).site(15, line: 21).foregroundStyle(Site.c3).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 24).padding(.top, 28)
                        VStack(alignment: .leading, spacing: 0) { content }.padding(.bottom, 24)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(step)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        // The button sits in its own bar in the page colour, so a long page (an open proxy app at a
        // larger text size) scrolls up out from under it instead of showing through around it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            mainButton.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
                .frame(maxWidth: .infinity)
                .background(Site.page(scheme).ignoresSafeArea(edges: .bottom))
        }
        .onChange(of: checkedByPhone) { was, now in
            if !was, now, step != .loopback { advanceSoon() }
        }
        // The loopback moves on when it comes on while this page is open, not when the first check finds
        // it already on.
        .onChange(of: model.loopback.state) { was, now in
            if step == .loopback, was == .off || was == .noAnswer, model.loopback.isWorking { advanceSoon() }
        }
        .onAppear { model.loopback.resume() }
        // Leaving the pairing step in Poki (another step, or closing setup) stops the pairing and its
        // background keep-alive. Going to Settings is not leaving.
        .onChange(of: index) { old, _ in if steps[old] == .pairing { model.leftPairing() } }
        .onDisappear { model.leftPairing() }
    }

    /// The current step's own check passed: the pairing took, location and Live Activities are on.
    private var checkedByPhone: Bool { step == .pairing || step == .background ? model.isDone(step) : false }

    private var header: some View {
        HStack(spacing: 12) {
            Button { index == 0 ? dismiss() : withAnimation(.snappy) { index -= 1 } } label: {
                Text(verbatim: "‹").site(17, line: 22).frame(minWidth: 20, minHeight: 32, alignment: .leading).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(index == 0 ? Text("Close") : Text("Back"))
            HStack(spacing: 4) {
                ForEach(steps.indices, id: \.self) { i in
                    Capsule().fill(i <= index ? Color.white : Color.white.opacity(0.28)).frame(height: 4)
                }
            }
            .accessibilityHidden(true)
            Text("\(index + 1) of \(steps.count)").site(13, line: 16).foregroundStyle(Site.c4).monospacedDigit()
        }
        .padding(.horizontal, 20).padding(.top, 8)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .runner:
            InstructionsCard(lines: [
                "Install **Poki Runner** (poki-runner-unsigned.ipa) with the same tool and Apple ID you used for Poki.",
                "Open **Settings › General › VPN & Device Management**, tap your Apple ID, then tap **Trust**.",
                "Don’t open Poki Runner yourself. Poki starts it when an agent needs this iPhone.",
            ])
            SetupFootnote(text: "With a free Apple ID, self-signed apps expire after 7 days and are limited to 3 at a time; Poki and Poki Runner use 2. For free Apple ID signing, install the external-connection build and use LocalDevVPN or a compatible VPN app.")
            ConfirmCard(step: .runner, title: "Poki Runner is installed and trusted", isOn: binding(\.runnerInstalled))
        case .developerMode:
            InstructionsCard(lines: [
                SetupStep.inProcess ? "Open **Settings › Privacy & Security › Developer Mode**." : "Open **Settings › Privacy & Security › Developer Mode**. It appears once Poki Runner is installed.",
                "Turn on Developer Mode, then tap **Restart**.",
                "After restarting, unlock this iPhone and tap **Turn On**.",
            ])
            ConfirmCard(step: .developerMode, title: "Developer Mode is on", isOn: binding(\.developerMode))
        case .loopback: LoopbackPage()
        case .pairing: PairingPage()
        case .automation:
            InstructionsCard(lines: [
                "Open **Settings › Developer**. It appears once Developer Mode is on.",
                "Turn on **Enable UI Automation**.",
            ])
            ConfirmCard(step: .automation, title: "UI Automation is on", isOn: binding(\.uiAutomation))
        case .background: BackgroundPage()
        }
    }

    private func binding(_ key: WritableKeyPath<SetupState, Bool>) -> Binding<Bool> {
        Binding(get: { model.setup[keyPath: key] }, set: { model.setup[keyPath: key] = $0 })
    }

    @ViewBuilder private var mainButton: some View {
        if step == .pairing, let action = PairingPage.mainAction(model) {
            CapsuleButton(title: action.title, height: 54) { action.run(model) }
        } else if index == steps.count - 1 {
            CapsuleButton(title: "Done", height: 54) { dismiss() }
        } else {
            CapsuleButton(title: "Continue", height: 54, enabled: model.isDone(step)) { advance() }
        }
    }

    private func advanceSoon() {
        let from = index
        Task { try? await Task.sleep(for: .milliseconds(600)); if index == from { advance() } }
    }

    private func advance() {
        guard index < steps.count - 1 else { return }
        withAnimation(.snappy) { index += 1 }
    }
}

extension SetupStep {
    /// The page's title (board 03: title case).
    var pageTitle: LocalizedStringKey {
        switch self {
        case .runner: "Install Poki Runner"
        case .developerMode: "Turn On Developer Mode"
        case .loopback: "Turn On Loopback"
        case .pairing: "Pair This iPhone"
        case .automation: "Allow UI Automation"
        case .background: "Keep Poki Running"
        }
    }

    var pageSummary: LocalizedStringKey {
        switch self {
        case .runner: "The helper app that taps and types for your agent. Poki starts it; you never open it."
        case .developerMode: SetupStep.inProcess ? "Allows Poki to use this iPhone’s developer services." : "Allows this iPhone to run Poki Runner."
        case .loopback: "Allows Poki to reach this iPhone’s developer services through your proxy app."
        case .pairing: "Gives Poki its own key to this iPhone. The key stays on this device."
        case .automation: SetupStep.inProcess ? "Allows Poki to control other apps." : "Allows Poki Runner to control other apps."
        case .background: "Keeps Poki connected in the background and shows its activity on the Lock Screen."
        }
    }
}

/// Opens Settings with the step in the Live Activity.
@MainActor func openSettings(_ model: AppModel, for step: SetupStep?) {
    if let step { model.guide(step) }
    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
}

private struct InstructionsCard: View {
    var lines: [String]
    var body: some View {
        NumberedLines(lines: lines).padding(16).glassCard()
            .padding(.horizontal, 20).padding(.top, 24)
    }
}

private struct SetupFootnote: View {
    var text: LocalizedStringKey
    var body: some View {
        Text(text).site(13, line: 18).foregroundStyle(Site.c4).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 36).padding(.top, 10)
    }
}

/// Open Settings and the switch for a step the phone can't check.
private struct ConfirmCard: View {
    @Environment(AppModel.self) private var model
    var step: SetupStep
    var title: LocalizedStringKey
    @Binding var isOn: Bool
    var body: some View {
        VStack(spacing: 0) {
            OpenSettingsRow(step: step)
            Toggle(isOn: $isOn) { Text(title).site(17, line: 22).frame(maxWidth: .infinity, alignment: .leading) }
                .toggleStyle(SiteToggleStyle())
                .padding(.vertical, 10).padding(.horizontal, 16)
        }
        .glassCard()
        .padding(.horizontal, 20).padding(.top, 20)
    }
}

private struct OpenSettingsRow: View {
    @Environment(AppModel.self) private var model
    var step: SetupStep
    var divider = true
    var body: some View {
        Button { openSettings(model, for: step) } label: {
            HStack(spacing: 10) {
                Image(systemName: "gear").font(.system(size: 17)).frame(width: 18)
                Text("Open Settings").site(17, line: 22).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 13).padding(.horizontal, 16).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { if divider { Site.edge.frame(height: 1) } }
    }
}

/// A row of plain text actions inside a glass card: "Import Pairing File ›", "Cancel Pairing".
private struct GlassActionRow: View {
    var title: LocalizedStringKey
    var color: Color = .white
    var chevron = false
    var divider = true
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).site(17, line: 22).foregroundStyle(color)
                Spacer()
                if chevron { Text(verbatim: "›").site(17, line: 22).foregroundStyle(Site.c4) }
            }
            .padding(.vertical, 13).padding(.horizontal, 16).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { if divider { Site.edge.frame(height: 1) } }
    }
}

private struct SectionCaption: View {
    var text: LocalizedStringKey
    var body: some View {
        Text(text).site(13, line: 16).foregroundStyle(Site.c4)
            .padding(.leading, 36).padding(.trailing, 20).padding(.top, 24).padding(.bottom, 8)
    }
}

/// An icon and a sentence on the blue: a problem, a state.
private struct NoteLine: View {
    var symbol: String
    var color: Color = .white
    var text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
            Text(text).site(15, line: 20).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: 3, loopback

/// The loopback, checked live, and the proxy apps that can provide it.
private struct LoopbackPage: View {
    @Environment(AppModel.self) private var model
    @State private var open: String?
    @State private var otherOpen = false
    @State private var copied = false

    var body: some View {
        let monitor = model.loopback
        HStack(spacing: 12) {
            Circle().fill(monitor.isWorking ? Site.ok : monitor.state == .checking || monitor.state == .off ? Color.white : Site.bad)
                .frame(width: 10, height: 10)
                .background(Circle().fill(Color.white.opacity(0.22)).padding(-5))
                .padding(5)
            VStack(alignment: .leading, spacing: 1) {
                Text(headline(monitor)).site(15, .semibold, line: 18)
                Text(monitor.isWorking ? LocalizedStringKey(monitor.detail) : monitor.state == .noAnswer ? LocalizedStringKey(monitor.detail) : "Checking 10.7.0.1 every few seconds…")
                    .site(13, line: 16).foregroundStyle(Site.c3).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14).padding(.horizontal, 11)
        .glassCard(fill: Site.glass2)
        .padding(.horizontal, 20).padding(.top, 20)
        .accessibilityElement(children: .combine)

        // The external app is the way (ESP-168): its list is always shown and always open to read.
        // The built-in connection is kept, folded under Other Ways at the bottom.
        SectionCaption(text: "USE YOUR PROXY APP")
        VStack(spacing: 0) {
            ForEach(ProxyApps.all) { app in proxyRow(app) }
            localDevVPN
        }
        .whiteCard()
        .padding(.horizontal, 20)
        .disabled(externalLocked)
        if let chosen = model.setup.proxyApp, !model.loopback.isWorking, model.setup.loopback == .proxy {
            let name = ProxyApps.all.first { $0.id == chosen }?.name ?? "LocalDevVPN"
            SetupFootnote(text: "\(name) is chosen, but nothing answers at 10.7.0.1 right now. Open \(name), make sure it is connected with the loopback on, then come back; this page updates by itself.")
        }
        otherWays
        Color.clear.frame(height: 0).onAppear {
            if open == nil { open = model.setup.proxyApp }
            if model.setup.loopback == .builtIn { otherOpen = true }
        }
    }

    /// The connection cannot change while Poki is on or pairing, or while the tunnel is changing.
    private var connectionLocked: Bool { model.connectionInUse || model.tunnel.busy }
    /// Reading and following an app's steps is always fine; only moving off a built-in connection that
    /// Poki is using waits.
    private var externalLocked: Bool { model.setup.loopback == .builtIn && connectionLocked }

    /// Other Ways: the built-in connection, folded.
    @ViewBuilder private var otherWays: some View {
        SectionCaption(text: "OTHER WAYS")
        VStack(spacing: 0) {
            Button { withAnimation(.snappy) { otherOpen.toggle() } } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Built-in").site(17, line: 22)
                        Text("No extra app").site(13, line: 16).foregroundStyle(Site.c3)
                    }
                    Spacer(minLength: 0)
                    if model.setup.loopback == .builtIn {
                        Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold))
                    }
                    Text(verbatim: otherOpen ? "⌄" : "›").site(17, line: 22).foregroundStyle(Site.c4)
                }
                .padding(.vertical, 11).padding(.horizontal, 16).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(otherOpen ? Text("Expanded") : Text("Collapsed"))
            if otherOpen {
                Site.edge.frame(height: 1)
                if model.tunnel.available {
                    builtIn
                    if model.setup.loopback == .builtIn {
                        GlassActionRow(title: "Use the Current VPN", chevron: false, divider: false) { model.chooseConnection(.proxy) }
                            .disabled(connectionLocked)
                    }
                } else {
                    #if targetEnvironment(simulator)
                    NoteLine(symbol: "info.circle", text: String(localized: "The built-in connection runs on a physical iPhone. Use your proxy app above."))
                        .padding(.horizontal, 16).padding(.vertical, 13)
                    #else
                    NoteLine(symbol: "info.circle", text: String(localized: "This build uses an external connection. For the built-in connection, install the local-VPN build with signing that supports Network Extensions."))
                        .padding(.horizontal, 16).padding(.vertical, 13)
                    #endif
                }
            }
        }
        .glassCard()
        .padding(.horizontal, 20)
        if otherOpen, model.connectionInUse, model.tunnel.available {
            SetupFootnote(text: "Stop Poki and finish pairing before changing the local connection.")
        }
    }

    @ViewBuilder private var builtIn: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("No extra app needed. Poki connects only to this iPhone; your normal internet traffic and DNS stay on their usual routes.")
                    .site(15, line: 20).fixedSize(horizontal: false, vertical: true)
                Text("iOS shows this as a VPN. Enabling it may disconnect another VPN app. To keep a compatible VPN, use your proxy app above instead.")
                    .site(13, line: 18).foregroundStyle(Site.c3).fixedSize(horizontal: false, vertical: true)
                switch model.tunnel.state {
                case .connecting: NoteLine(symbol: "hourglass", text: String(localized: "Connecting to this iPhone…"))
                case .disconnecting: NoteLine(symbol: "hourglass", text: String(localized: "Disconnecting…"))
                case .connected: NoteLine(symbol: "network", color: Site.ok, text: String(localized: "Local VPN connected. The check above confirms developer access."))
                case .failed(let message): NoteLine(symbol: "exclamationmark.triangle", color: Site.bad, text: Bundle.main.localizedString(forKey: message, value: message, table: nil))
                case .off, .unavailable: EmptyView()
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .overlay(alignment: .bottom) { Site.edge.frame(height: 1) }
            switch model.tunnel.state {
            case .connecting:
                GlassActionRow(title: "Cancel Connection", color: Color(hex: 0xFFC9C5), divider: false) { model.tunnel.disconnect() }
                    .disabled(connectionLocked)
            case .connected:
                GlassActionRow(title: "Disconnect Local Connection", divider: false) { model.tunnel.disconnect() }
                    .disabled(connectionLocked)
            case .failed, .off: enableButton
            case .disconnecting, .unavailable: EmptyView()
            }
        }
    }

    /// Also while Poki is on with the built-in connection: reconnecting it is how the owner recovers
    /// when it drops mid-session (the agent is told to tap this), and it changes no choice.
    private var enableButton: some View {
        GlassActionRow(title: "Enable Local Connection", divider: false) {
            model.chooseConnection(.builtIn)
            Task { try? await model.tunnel.connect(); model.loopback.check() }
        }
        .disabled(model.tunnel.busy || (model.connectionInUse && model.setup.loopback != .builtIn))
    }

    private func headline(_ monitor: LoopbackMonitor) -> LocalizedStringKey {
        switch monitor.state {
        case .working: "Loopback is on"
        case .noAnswer: "Tunnel on, no answer"
        default: "Not on yet"
        }
    }

    private func rowHeader(_ name: String, tag: Text?, tagInUse: Bool, tagBad: Bool = false, sub: Text?, id: String) -> some View {
        Button { withAnimation(.snappy) { open = open == id ? nil : id } } label: {
            HStack(spacing: 10) {
                Text(verbatim: name).site(17, line: 22).foregroundStyle(Site.text)
                if let tag {
                    tag.site(11, .semibold, line: 14).foregroundStyle(tagInUse ? Site.okInk : tagBad ? Color(hex: 0xB42318) : Site.ink)
                        .padding(.vertical, 2).padding(.horizontal, 7)
                        .background(tagInUse ? Color(hex: 0x3CCF7A).opacity(0.16) : tagBad ? Color(hex: 0xF04438).opacity(0.14) : Site.tint, in: .rect(cornerRadius: 6))
                }
                if let sub { sub.site(13, line: 16).foregroundStyle(Site.text3) }
                Spacer(minLength: 0)
                Text(verbatim: open == id ? "⌄" : "›").site(17, line: 22).foregroundStyle(Site.text3)
            }
            .padding(.vertical, 13).padding(.horizontal, 16).contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func proxyRow(_ app: ProxyApp) -> some View {
        let chosen = model.setup.proxyApp == app.id
        let expanded = open == app.id
        // The tag says what is true now: the chosen app is "Working" only while 10.7.0.1 answers;
        // chosen and silent reads "Not Answering" (the card above says what to do).
        let working = chosen && model.loopback.isWorking
        rowHeader(app.name, tag: working ? Text("Working") : chosen ? Text("Not Answering") : app.isInstalled ? Text("Installed") : nil, tagInUse: working, tagBad: chosen && !working,
                  sub: expanded && !app.minimumVersion.isEmpty ? Text("\(app.minimumVersion) or later") : nil, id: app.id)
        if expanded {
            VStack(alignment: .leading, spacing: 10) {
                NumberedLines(lines: app.steps, onWhite: true)
                if !app.documented {
                    Text("As reported by users of \(app.name); not checked against its documentation. The check at the top tells whether it works.")
                        .site(12, line: 16).foregroundStyle(Site.text3).fixedSize(horizontal: false, vertical: true)
                }
                if chosen, !working, case .snippet = app.install {
                    inkLink("Open \(app.name)") { if let url = URL(string: "\(app.scheme)://") { UIApplication.shared.open(url) } }
                }
                switch app.install {
                case .url(let url):
                    inkLink(app.id == "surge" ? "Install Poki Module" : "Install Poki Plugin") { choose(app); UIApplication.shared.open(url) }
                case .toggle:
                    inkLink("Open \(app.name)") { choose(app); if let url = URL(string: "\(app.scheme)://") { UIApplication.shared.open(url) } }
                case .snippet(let line):
                    HStack(spacing: 8) {
                        Text(verbatim: line).mono(12).foregroundStyle(Site.text).textSelection(.enabled)
                        Spacer(minLength: 0)
                        Button { choose(app); UIPasteboard.general.string = line; copied = true } label: {
                            Text(copied ? "Copied" : "Copy").site(14, .semibold, line: 18).foregroundStyle(Site.ink)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 9).padding(.leading, 12).padding(.trailing, 10)
                    .background(Color(hex: 0xF2F3F5), in: .rect(cornerRadius: 10))
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 14)
        }
        Site.hair.frame(height: 1)
    }

    @ViewBuilder private var localDevVPN: some View {
        let id = "localdevvpn"
        let chosen = model.setup.proxyApp == id
        let working = chosen && model.loopback.isWorking
        rowHeader("LocalDevVPN", tag: working ? Text("Working") : chosen ? Text("Not Answering") : nil, tagInUse: working, tagBad: chosen && !working, sub: Text("Free on the App Store"), id: id)
        if open == id {
            VStack(alignment: .leading, spacing: 10) {
                NumberedLines(lines: [
                    "No proxy app? Install LocalDevVPN, a free loopback app built for this.",
                    "Open it and tap Connect, then return to Poki. It may disconnect another VPN app.",
                ], onWhite: true)
                inkLink("Get LocalDevVPN on the App Store") {
                    model.chooseConnection(.proxy); model.setup.proxyApp = id; model.guide(.loopback)
                    UIApplication.shared.open(URL(string: "https://apps.apple.com/app/id6755608044")!)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 14)
        }
    }

    private func inkLink(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).site(15, .semibold, line: 20).foregroundStyle(Site.ink) }.buttonStyle(.plain)
    }

    private func choose(_ app: ProxyApp) {
        model.chooseConnection(.proxy)
        model.setup.proxyApp = app.id
        model.guide(.loopback)
    }
}

// MARK: 4, pairing

private struct PairingPage: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false
    @State private var importError: String?

    struct MainAction {
        var title: LocalizedStringKey
        var run: @MainActor (AppModel) -> Void
    }

    /// The pairing page's own main button; nil leaves Continue.
    @MainActor static func mainAction(_ model: AppModel) -> MainAction? {
        switch model.pairing {
        case .pin?: return MainAction(title: "Open Settings") { openSettings($0, for: .pairing) }
        case .advertising?: return nil
        case .failed?: return MainAction(title: "Try Again") { pair($0) }
        default:
            guard SetupStep.onDevicePairing else { return nil }
            if model.pairingTrouble != nil { return MainAction(title: "Pair Again") { pair($0) } }
            if model.pairingPath == nil { return MainAction(title: "Start Pairing") { pair($0) } }
            return nil
        }
    }

    @MainActor static func pair(_ model: AppModel) {
        model.startPairing()
        openSettings(model, for: .pairing)
    }

    var body: some View {
        Group {
            switch model.pairing {
            case .pin(let pin)?: code(pin)
            case .advertising?:
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 14, weight: .semibold))
                            .symbolEffect(.pulse, options: .repeating)
                        Text("Waiting for Settings. Tap Pair with Poki there.").site(15, .semibold, line: 20)
                    }
                    NumberedLines(lines: [
                        "Open **Settings › Privacy & Security › Developer Mode**.",
                        "Tap **Pair with Poki** and enter the code shown here and on the Lock Screen.",
                    ])
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard()
                .padding(.horizontal, 20).padding(.top, 24)
                VStack(spacing: 0) {
                    OpenSettingsRow(step: .pairing)
                    GlassActionRow(title: "Cancel Pairing", color: Color(hex: 0xFFC9C5), divider: false) { model.cancelPairing() }
                }
                .glassCard().padding(.horizontal, 20).padding(.top, 16)
            case .failed(let why)?:
                NoteLine(symbol: "exclamationmark.triangle", text: why).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard().padding(.horizontal, 20).padding(.top, 24)
            default:
                if let trouble = model.pairingTrouble {
                    VStack(alignment: .leading, spacing: 8) {
                        NoteLine(symbol: "exclamationmark.triangle", text: String(localized: "The phone no longer accepts this pairing: \(trouble)"))
                        Text(SetupStep.onDevicePairing ? "This happens after a restore, a reset of Location & Privacy, or when the phone forgot Poki. Pair again; the old key is replaced." : "This happens after a restore, a reset of Location & Privacy, or when the phone forgot Poki. Pair again from Poki Setup on your computer and send the new file here; the old key is replaced.")
                            .site(13, line: 18).foregroundStyle(Site.c3).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard()
                    .padding(.horizontal, 20).padding(.top, 24)
                } else if model.pairingPath != nil {
                    NoteLine(symbol: "checkmark.seal.fill", color: Site.ok,
                             text: model.pairingVerifiedAt.map { String(localized: "Paired. The phone accepted it at \($0.formatted(date: .omitted, time: .shortened)).") }
                                ?? String(localized: "Paired. Checked the next time the runner starts."))
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading).glassCard()
                        .padding(.horizontal, 20).padding(.top, 24)
                } else if SetupStep.onDevicePairing {
                    InstructionsCard(lines: [
                        "Connect to Wi‑Fi and tap **Start Pairing**. Allow local network access when prompted.",
                        "Poki will open Settings. Go to **Privacy & Security › Developer Mode** and tap **Pair with Poki**.",
                        "Enter the code shown here and on the Lock Screen.",
                    ])
                } else {
                    fromComputer
                }
            }
        }
        if let note = model.pairingNote {
            NoteLine(symbol: note.hasPrefix(String(localized: "Pairing file received.")) ? "checkmark.circle.fill" : "info.circle",
                     color: note.hasPrefix(String(localized: "Pairing file received.")) ? Site.ok : .white, text: note)
                .padding(.horizontal, 36).padding(.top, 10)
        }
        diskImage.padding(.horizontal, 20).padding(.top, 14)
        SectionCaption(text: "OTHER WAYS")
        VStack(spacing: 0) {
            GlassActionRow(title: "Import Pairing File", chevron: true, divider: cancelShown || pairAgainShown) { importing = true }
            if pairAgainShown {
                GlassActionRow(title: "Pair Again", divider: cancelShown) { Self.pair(model) }
            }
            if cancelShown {
                GlassActionRow(title: "Cancel Pairing", color: Color(hex: 0xFFC9C5), divider: false) { model.cancelPairing() }
            }
        }
        .glassCard().padding(.horizontal, 20)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.propertyList, .xml, .data]) { result in
            do { try model.importPairingFile(from: result.get()); importError = nil }
            catch { importError = String(localized: "Invalid Pairing File: \(error.localizedDescription)") }
        }
        if let importError {
            Text(importError).site(13, line: 18).foregroundStyle(Color(hex: 0xFFC9C5))
                .padding(.horizontal, 36).padding(.top, 8)
        }
    }

    private var cancelShown: Bool { if case .pin? = model.pairing { true } else { false } }
    /// Paired and fine: pairing again is the other way (on the phone itself, iOS 27 and later).
    private var pairAgainShown: Bool { SetupStep.onDevicePairing && model.pairing == nil && model.pairingTrouble == nil && model.pairingPath != nil }

    /// Before iOS 27 the phone cannot pair with itself: the pairing file is made on a computer with
    /// Poki Setup (or any tool that writes a lockdown pairing file) and sent here.
    @ViewBuilder private var fromComputer: some View {
        InstructionsCard(lines: [
            "Pairing on the phone itself needs iOS 27; this iPhone runs iOS \(UIDevice.current.systemVersion). Pair it from a computer instead.",
            "Open **Poki Setup** on your Mac or PC, connect this iPhone by cable, and tap **Pair**. Tap **Trust** on the iPhone when asked.",
            "Send the pairing file here: scan the code Poki Setup shows with the Camera, AirDrop the file to this iPhone and open it with Poki, or tap **Import Pairing File** below.",
        ])
        SetupFootnote(text: "No Poki Setup yet? Any lockdown pairing file works: pymobiledevice3, jitterbugpair or StikPair make one. Import it below.")
    }

    private func code(_ pin: String) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(Array(pin.enumerated()), id: \.offset) { i, digit in
                    if i == 3 && pin.count == 6 { Color.clear.frame(width: 4, height: 1) }
                    Text(verbatim: String(digit)).site(34, .heavy, line: 42).monospacedDigit()
                        .frame(width: 44, height: 58)
                        .background(Site.glass2, in: .rect(cornerRadius: 12, style: .continuous))
                        .contentTransition(.numericText())
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: pin.map(String.init).joined(separator: " ")))
            Text("Enter this code in Settings. It also appears on the Lock Screen.").site(15, line: 21).foregroundStyle(Site.c3)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24).padding(.horizontal, 16).padding(.bottom, 20)
        .glassCard(20)
        .padding(.horizontal, 20).padding(.top, 24)
    }

    @ViewBuilder private var diskImage: some View {
        switch model.diskImage.state {
        case .ready:
            HStack(spacing: 8) { StatusDot(color: Site.ok, size: 8); Text("Developer Disk Image Ready").site(13, line: 16).foregroundStyle(Site.c4) }
        case .downloading(let step):
            HStack(spacing: 8) {
                ProgressView().controlSize(.mini).tint(Site.c4)
                Text("Downloading Developer Disk Image: \(step)").site(13, line: 16).foregroundStyle(Site.c4)
            }
        case .missing:
            Button { Task { await model.diskImage.download() } } label: {
                Text("Download Developer Disk Image").site(15, .semibold, line: 20)
            }
            .buttonStyle(.plain)
        case .failed(let why):
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 13, weight: .semibold))
                    Text(why).site(14, line: 19).foregroundStyle(Site.c3).fixedSize(horizontal: false, vertical: true)
                }
                Button { Task { await model.diskImage.download() } } label: { Text("Download Again").site(15, .semibold, line: 20) }
                    .buttonStyle(.plain).padding(.leading, 21)
            }
        }
    }
}

// MARK: 6, background

private struct BackgroundPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 12) {
            card(symbol: model.background.allowed ? "checkmark.circle.fill" : model.background.denied ? "exclamationmark.triangle" : "location",
                 color: model.background.allowed ? Site.ok : .white,
                 title: "Location",
                 text: model.background.allowed ? "Location allowed. Poki stays active in the background and never records your location."
                     : model.background.denied ? "Location Services is off for Poki, so iOS will suspend it shortly after you leave the app."
                     : "iOS requires a background mode to keep apps running. Poki uses lowest-accuracy location and shows the location indicator while active.",
                 action: model.background.allowed ? nil : model.background.denied ? ("Open Settings", { openSettings(model, for: .background) })
                     : ("Allow Location Access", { model.background.requestPermission() }))
            card(symbol: model.activitiesEnabled ? "checkmark.circle.fill" : "exclamationmark.triangle",
                 color: model.activitiesEnabled ? Site.ok : .white,
                 title: model.activitiesEnabled ? "Live Activities are on" : "Live Activities are off",
                 text: model.activitiesEnabled ? "Poki shows steps, pairing codes, and approvals on the Lock Screen."
                     : "Live Activities are off for Poki. Turn them on to view agent steps and approve sensitive actions.",
                 action: model.activitiesEnabled ? nil : ("Open Settings", { openSettings(model, for: .background) }))
        }
        .padding(.horizontal, 20).padding(.top, 24)
        SetupFootnote(text: SetupStep.inProcess ? "The first time Poki turns on after a restart, iOS asks for your passcode to allow automation. Enter it once; Poki never sees it." : "The first time Poki Runner starts after a restart, iOS asks for your passcode to allow automation. Enter it once; Poki never sees it.")
            .padding(.top, 8)
    }

    private func card(symbol: String, color: Color, title: LocalizedStringKey, text: LocalizedStringKey,
                      action: (LocalizedStringKey, () -> Void)?) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(color).frame(width: 20, height: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).site(17, line: 22)
                    Text(text).site(14, line: 19).foregroundStyle(Site.c3).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 13).padding(.horizontal, 16)
            if let action {
                Site.edge.frame(height: 1)
                Button(action: action.1) {
                    Text(action.0).site(17, line: 22).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 13).padding(.leading, 48).padding(.trailing, 16).contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .glassCard()
    }
}
