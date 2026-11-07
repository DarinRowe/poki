import CoreImage.CIFilterBuiltins
import PokiCore
import SwiftUI

/// Settings, the sheet behind Home's gear (ESP-139 board 04): this iPhone and its relay, the agents
/// (one MCP address each, revocable), the runner, and setup and diagnostics. White cards on the blue.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var path: [SettingsRoute]
    var openSetup: () -> Void

    init(start: [SettingsRoute] = [], openSetup: @escaping () -> Void) {
        _path = State(initialValue: start)
        self.openSetup = openSetup
    }

    var body: some View {
        NavigationStack(path: $path) {
            SettingsHome(path: $path, openSetup: openSetup, done: { dismiss() })
                .navigationDestination(for: SettingsRoute.self) { route in
                    switch route {
                    case .connector(let secret): ConnectorDetail(secret: secret, back: { path.removeLast() })
                    case .relay: RelayView(back: { path.removeLast() })
                    case .diagnostics: DiagnosticsView(path: $path)
                    case .log: LogView(back: { path.removeLast() })
                    case .memory: MemoryView(back: { path.removeLast() })
                    case .activityPreview: ActivityPreview()
                    }
                }
        }
        .presentationDragIndicator(.hidden)
        .presentationBackground(Site.page(scheme))
    }
}

enum SettingsRoute: Hashable {
    case connector(ConnectorSecret), relay, diagnostics, log, activityPreview, memory
}

private struct SettingsHome: View {
    @Environment(AppModel.self) private var model
    @Binding var path: [SettingsRoute]
    var openSetup: () -> Void
    var done: () -> Void
    @State private var newName = ""

    var body: some View {
        SitePage {
            VStack(spacing: 0) {
                Grabber()
                SheetHeader(title: Text("Settings"), sideWidth: 60, done: done)
                ScrollView {
                    VStack(spacing: 0) {
                        thisIPhone.padding(.top, 4)
                        GroupFootnote(text: "The relay forwards requests to this iPhone while Poki is open or in the background. It stores nothing; when offline, clients receive an error.")
                        agents
                        // The in-process path has no Poki Runner to start or stop (ESP-152).
                        if model.automationPath == .runner { runner }
                        phone
                    }
                    .padding(.horizontal, 16).padding(.bottom, 40)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var thisIPhone: some View {
        HStack(spacing: 12) {
            BearAvatar(size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("This iPhone").site(17, .semibold, line: 22).foregroundStyle(Site.text)
                Text(verbatim: model.identity.label.isEmpty ? "—" : "\(model.identity.label.prefix(12))…").mono(13).foregroundStyle(Site.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            let relay = Health.relay(model)
            HStack(spacing: 6) {
                StatusDot(color: relay.color == Site.ok ? Site.okInk : relay.color == Site.bad ? Site.danger : Site.text3)
                Text(relay.word).site(15, line: 18)
            }
            .foregroundStyle(relay.color == Site.ok ? Site.okInk : relay.color == Site.bad ? Site.danger : Site.text3)
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
        .whiteCard()
    }

    @ViewBuilder private var agents: some View {
        GroupLabel(text: "AGENTS")
        VStack(spacing: 0) {
            ForEach(model.identity.secrets) { secret in
                Button { path.append(.connector(secret)) } label: {
                    WhiteRow(title: LocalizedStringKey(secret.name)) {
                        RowValue(text: Text(secret.created.formatted(.dateTime.month(.abbreviated).day())))
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.relayAddress == nil)
                .contextMenu { Button("Revoke Access", systemImage: "xmark.circle", role: .destructive) { model.revoke(secret) } }
            }
            HStack {
                TextField(text: $newName, prompt: Text("Name, e.g., Claude").foregroundStyle(Site.text3)) { Text("Name") }
                    .site(17, line: 22).foregroundStyle(Site.text)
                    .submitLabel(.done).onSubmit(add)
                Button(action: add) { Text("Add").site(17, line: 20).foregroundStyle(model.relayAddress == nil ? Site.text3 : Site.ink) }
                    .buttonStyle(.plain).frame(height: 32)
                    .disabled(model.relayAddress == nil)
            }
            .padding(.vertical, 8).padding(.horizontal, 16)
        }
        .whiteCard()
        if model.relayAddress == nil {
            GroupFootnote(text: "Set your relay address first: each agent’s address is on your relay.")
        }
        if let error = model.identity.error {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 15)).foregroundStyle(Site.danger)
                Text(Self.friendly(error)).site(15, line: 20).foregroundStyle(Site.text).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14).padding(.horizontal, 16)
            .whiteCard()
            .padding(.top, 12)
        }
    }

    private func add() {
        guard model.relayAddress != nil else { return }
        let secret = model.addConnector(name: newName.trimmingCharacters(in: .whitespaces))
        newName = ""
        path.append(.connector(secret))
    }

    @ViewBuilder private var runner: some View {
        @Bindable var model = model
        GroupLabel(text: "RUNNER")
        VStack(spacing: 0) {
            WhiteRow(title: "Runner") { RowValue(text: Text(Health.runner(model).word), chevron: false) }
            WhiteRow(title: "Stop When Idle For") {
                Menu {
                    Picker(selection: $model.idleStopSeconds) {
                        ForEach(Self.idleChoices, id: \.0) { Text($0.1).tag($0.0) }
                    } label: { Text("Stop When Idle For") }
                } label: {
                    HStack(spacing: 4) {
                        Text(Self.idleChoices.first { $0.0 == model.idleStopSeconds }?.1 ?? "\(model.idleStopSeconds) s")
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .medium))
                    }
                    .site(15, line: 18).foregroundStyle(Site.text3)
                }
            }
            if model.runnerPaused {
                Button { model.wakeRunner() } label: { WhiteRow(title: "Start Now", titleColor: Site.ink, divider: false) }
                    .buttonStyle(.plain)
            } else {
                Button { model.pauseRunner() } label: { WhiteRow(title: "Stop Runner", titleColor: model.approvals.isEmpty ? Site.danger : Site.text3, divider: false) }
                    .buttonStyle(.plain)
                    .disabled(!model.approvals.isEmpty)
            }
        }
        .whiteCard()
        if model.automationPath == .inProcess {
            GroupFootnote(text: "iOS shows the automation banner only while Poki’s automation session is open. Poki opens it when an agent asks and closes it when idle.")
        } else {
            GroupFootnote(text: "iOS shows the automation banner only while the runner is active. Poki starts it when needed and stops it when idle. Don’t close Poki Runner while an agent is working.")
        }
    }

    static let idleChoices: [(Int, LocalizedStringKey)] = [
        (30, "30 seconds"), (60, "1 minute"), (120, "2 minutes"), (300, "5 minutes"), (0, "Never"),
    ]

    @ViewBuilder private var phone: some View {
        let done = SetupStep.shown.filter(model.isDone).count
        let total = SetupStep.shown.count
        GroupLabel(text: "THIS IPHONE")
        VStack(spacing: 0) {
            Button { path.append(.relay) } label: {
                WhiteRow(title: "Relay") {
                    RowValue(text: model.relayAddress.map { Text(verbatim: $0.origin.host() ?? $0.origin.absoluteString) } ?? Text("Not Set"),
                             color: model.relayAddress == nil ? Site.danger : Site.text3)
                }
            }
            .buttonStyle(.plain)
            Button { path.append(.memory) } label: {
                WhiteRow(title: "Memory") { RowValue(text: Text("\(RoutineStore.shared.routines.count) routines")) }
            }
            .buttonStyle(.plain)
            Button(action: openSetup) {
                WhiteRow(title: "Setup") { RowValue(text: Text("\(done) of \(total)"), color: done == total ? Site.okInk : Site.text3) }
            }
            .buttonStyle(.plain)
            Button { path.append(.diagnostics) } label: { WhiteRow(title: "Diagnostics", divider: false) { RowValue() } }
                .buttonStyle(.plain)
        }
        .whiteCard()
        GroupFootnote(text: "Memory holds the routines and notes every agent shares. Diagnostics: logs, checks, background hold, addresses, and Live Activity preview.")
    }

    /// Keychain errors in words. -34018 means the app's signature has no keychain access (an unsigned
    /// or wrongly signed build); everything else shows its code.
    static func friendly(_ error: String) -> String {
        if error.contains("-34018") {
            return String(localized: "Poki cannot access the keychain and has no relay key yet. Reinstall Poki with your signing tool, then reopen Settings.")
        }
        return String(localized: "Poki couldn’t read its relay key from the keychain (\(error)).")
    }
}

/// The person's own relay. There is no default: until it is set, Poki sends nothing anywhere. The
/// board does not draw this page; it is Settings' white card and footnote style.
private struct RelayView: View {
    @Environment(AppModel.self) private var model
    var back: () -> Void
    @State private var text = ""
    @State private var rejected = false
    @FocusState private var focused: Bool

    var body: some View {
        SitePage {
            VStack(spacing: 0) {
                Grabber()
                SheetHeader(title: Text("Relay"), back: "Settings", onBack: back)
                ScrollView {
                    VStack(spacing: 0) {
                        GroupLabel(text: "RELAY ADDRESS")
                        HStack {
                            TextField(text: $text, prompt: Text(verbatim: "https://poki-relay.you.workers.dev").foregroundStyle(Site.text3)) { Text("Relay Address") }
                                .mono(15).foregroundStyle(Site.text)
                                .keyboardType(.URL).textContentType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .focused($focused)
                                .submitLabel(.done).onSubmit(save)
                            Button(action: save) { Text("Save").site(17, line: 20).foregroundStyle(canSave ? Site.ink : Site.text3) }
                                .buttonStyle(.plain).disabled(!canSave)
                        }
                        .padding(.vertical, 12).padding(.horizontal, 16)
                        .whiteCard()
                        if rejected {
                            GroupFootnote(text: "That is not a relay address. Enter the address deploy.sh printed, such as https://poki-relay.you.workers.dev.")
                                .foregroundStyle(Color(hex: 0xFFC9C5))
                        }
                        GroupFootnote(text: "Poki has no default relay. Deploy your own to your Cloudflare account with deploy/cf-relay/deploy.sh from the Poki repository, then enter the address it prints. Screenshots and taps pass only through that relay.")
                        GroupLabel(text: "STATUS")
                        WhiteRow(title: "Relay", divider: false) { RowValue(text: Text(statusText), chevron: false) }.whiteCard()
                    }
                    .padding(.horizontal, 16).padding(.bottom, 40)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { text = model.relayAddress?.origin.absoluteString ?? ""; if model.relayAddress == nil { focused = true } }
    }

    private var canSave: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed != model.relayAddress?.origin.absoluteString
    }

    /// "Online", or "Offline: why" with PokiCore's reason as it came.
    private var statusText: String {
        if case .offline(let why) = model.relayStatus { return "\(Health.relay(model).word): \(why)" }
        return Health.relay(model).word
    }

    private func save() {
        rejected = !model.setRelay(text)
        if !rejected { focused = false }
    }
}

/// One agent's MCP address: a QR code, the address with its secret hidden, Copy, and Revoke.
private struct ConnectorDetail: View {
    @Environment(AppModel.self) private var model
    var secret: ConnectorSecret
    var back: () -> Void
    @State private var copied = false

    var body: some View {
        // Rows and Add open this only once a relay is set, so the address is there.
        let url = model.connectorURL(for: secret)?.absoluteString ?? ""
        SitePage {
            VStack(spacing: 0) {
                Grabber()
                SheetHeader(title: Text(verbatim: secret.name), back: "Settings", onBack: back)
                ScrollView {
                    VStack(spacing: 0) {
                        if let qr = QRCode.image(url) {
                            Image(uiImage: qr).interpolation(.none).resizable().scaledToFit()
                                .frame(width: 180, height: 180).padding(20)
                                .background(.white, in: .rect(cornerRadius: 24, style: .continuous))
                                .accessibilityLabel(Text("QR code of the address"))
                                .padding(.top, 12)
                        }
                        Text(verbatim: url.replacingOccurrences(of: secret.secret, with: "••••••"))
                            .mono(13).foregroundStyle(Site.c3).multilineTextAlignment(.center).lineSpacing(3)
                            .padding(.horizontal, 24).padding(.top, 20)
                        CapsuleButton(title: copied ? "Copied" : "Copy Address", height: 50) {
                            UIPasteboard.general.string = url
                            copied = true
                        }
                        .padding(.horizontal, 4).padding(.top, 20)
                        Text("Add this URL as a remote MCP server in your client. Anyone with this link can control this iPhone while Poki is running. Keep it private, and revoke it here if compromised.")
                            .site(13, line: 18).foregroundStyle(Site.c4).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20).padding(.top, 20)
                        VStack(spacing: 0) {
                            WhiteRow(title: "Added") { RowValue(text: Text(secret.created.formatted(date: .abbreviated, time: .omitted)), chevron: false) }
                            Button { model.revoke(secret); back() } label: { WhiteRow(title: "Revoke Access", titleColor: Site.danger, divider: false) }
                                .buttonStyle(.plain)
                        }
                        .whiteCard()
                        .padding(.top, 28)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 40)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

enum QRCode {
    static func image(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
