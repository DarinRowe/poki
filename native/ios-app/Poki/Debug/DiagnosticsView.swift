import SwiftUI

/// Diagnostics, under Settings (ESP-139 board 04, C): the log, the proxy's loopback interface, the
/// connection checks, the background hold experiment and the phone's addresses.
struct DiagnosticsView: View {
    @Binding var path: [SettingsRoute]
    @State private var results: [ProbeResult] = []
    @State private var running = false
    @State private var addresses: [LocalAddress] = localAddresses()
    @StateObject private var hold = Hold()
    @State private var log = AppLog.shared
    @State private var copied = false
    @Environment(AppModel.self) private var model

    var body: some View {
        SitePage {
            VStack(spacing: 0) {
                Grabber()
                SheetHeader(title: Text("Diagnostics"), back: "Settings", onBack: { path.removeLast() })
                ScrollView {
                    VStack(spacing: 0) {
                        logGroup
                        loopbackGroup
                        checksGroup
                        holdGroup
                        addressesGroup
                    }
                    .padding(.horizontal, 16).padding(.bottom, 40)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await run() }
    }

    @ViewBuilder private var logGroup: some View {
        GroupLabel(text: "LOG")
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = log.text
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(2)); copied = false }
                } label: {
                    Text(copied ? "Copied" : "Copy Log").site(15, .semibold, line: 18).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 40).background(Site.blue, in: .capsule)
                }
                .buttonStyle(.plain)
                ShareLink(item: log.text, subject: Text("Poki log")) {
                    Text("Share").site(15, .semibold, line: 18).foregroundStyle(Site.ink)
                        .frame(maxWidth: .infinity).frame(height: 40).background(Site.tint, in: .capsule)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 12).padding(.horizontal, 16)
            .overlay(alignment: .bottom) { Site.hair.frame(height: 1) }
            Button { path.append(.log) } label: { WhiteRow(title: "Log") { RowValue(text: Text("\(log.lines.count) lines")) } }
                .buttonStyle(.plain)
            Button { path.append(.activityPreview) } label: { WhiteRow(title: "Live Activity Preview", divider: false) { RowValue() } }
                .buttonStyle(.plain)
        }
        .whiteCard()
        GroupFootnote(text: "Runner starts and stops, agent steps, approvals, and connection changes. Password field entries are never logged.")
    }

    @ViewBuilder private var loopbackGroup: some View {
        GroupLabel(text: "PROXY LOOPBACK INTERFACE")
        VStack(alignment: .leading, spacing: 4) {
            if let loop = loopbackInterface(addresses) {
                Text(verbatim: "\(loop.interface)  \(loop.address)").mono(16, .semibold).foregroundStyle(Site.text)
                Text(loop.ipv6.isEmpty ? "No IPv6 on this interface" : "IPv6 present: \(loop.ipv6.joined(separator: ", "))")
                    .mono(12).foregroundStyle(loop.ipv6.isEmpty ? Site.text3 : Site.danger)
            } else {
                Text("No interface has a 10.7.0.x address. Check that your proxy app is on and its loopback module is enabled.")
                    .site(15, line: 20).foregroundStyle(Site.text2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12).padding(.horizontal, 16)
        .whiteCard()
        Text(verbatim: "Network path: \(model.loopback.pathSummary). Wi-Fi \(model.loopback.wifiUp ? "up" : "down"), cellular \(model.loopback.cellularUp ? "up" : "down")\(model.loopback.cellularOnly ? " (cellular only)" : "")")
            .mono(12).foregroundStyle(Site.text3).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 8)
    }

    @ViewBuilder private var checksGroup: some View {
        GroupLabel(text: "CHECKS")
        VStack(spacing: 0) {
            ForEach(results) { r in
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.title(r))
                        .site(15, .semibold, line: 20).foregroundStyle(Site.text)
                    Text(verbatim: "\(r.target)  \(r.milliseconds) ms").mono(12).foregroundStyle(Site.text3)
                    if !r.detail.isEmpty { Text(verbatim: r.detail).mono(12).foregroundStyle(Site.text2) }
                    if !r.firstBytes.isEmpty { Text(verbatim: "first bytes: \(r.firstBytes)").mono(12).foregroundStyle(Site.text2) }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12).padding(.horizontal, 16)
                .overlay(alignment: .bottom) { Site.hair.frame(height: 1) }
            }
            Button { Task { await run() } } label: {
                WhiteRow(title: running ? "Running…" : "Run Checks", titleColor: running ? Site.text3 : Site.ink, divider: false)
            }
            .buttonStyle(.plain).disabled(running)
        }
        .whiteCard()
    }

    @ViewBuilder private var holdGroup: some View {
        GroupLabel(text: "BACKGROUND HOLD")
        VStack(spacing: 0) {
            WhiteRow(title: "Port on 10.7.0.1") {
                TextField(text: $hold.port, prompt: Text(verbatim: "49152").foregroundStyle(Site.text3)) { Text("Port on 10.7.0.1") }
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing).monospacedDigit()
                    .site(17, line: 22).foregroundStyle(Site.text).frame(width: 90)
            }
            WhiteRow(title: "Experiment") {
                Menu {
                    Picker(selection: $hold.experiment) {
                        ForEach(Hold.Experiment.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                    } label: { Text("Experiment") }
                } label: {
                    HStack(spacing: 4) {
                        Text(LocalizedStringKey(hold.experiment.rawValue))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .medium))
                    }
                    .site(17, line: 22).foregroundStyle(Site.text3)
                }
                .disabled(hold.holding)
            }
            HStack {
                Button { hold.start() } label: { Text("Start Hold").site(17, line: 22).foregroundStyle(hold.holding ? Site.text3 : Site.ink) }
                    .disabled(hold.holding)
                Spacer()
                Button { hold.stop() } label: { Text("Stop").site(17, line: 22).foregroundStyle(hold.holding ? Site.danger : Site.text3) }
                    .disabled(!hold.holding)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 12).padding(.horizontal, 16)
            if !hold.log.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(hold.log.indices, id: \.self) { i in Text(verbatim: hold.log[i]).mono(11).foregroundStyle(Site.text2) }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12).padding(.horizontal, 16)
                .overlay(alignment: .top) { Site.hair.frame(height: 1) }
            }
        }
        .whiteCard()
        GroupFootnote(text: "Tap Start, leave the app for a while, then return. The log records suspension gaps and connection closures.")
    }

    @ViewBuilder private var addressesGroup: some View {
        GroupLabel(text: "ADDRESSES")
        VStack(alignment: .leading, spacing: 6) {
            ForEach(addresses.indices, id: \.self) { i in
                Text(verbatim: "\(addresses[i].interface)  \(addresses[i].address)").mono(12).foregroundStyle(Site.text2)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14).padding(.horizontal, 16)
        .whiteCard()
    }

    /// "Reflected lockdown: Connected", the probe's own words with the address left to the line below.
    static func title(_ r: ProbeResult) -> String {
        let label = r.label.replacingOccurrences(of: " (10.7.0.1)", with: "")
        let outcome = r.outcome.prefix(1).uppercased() + r.outcome.dropFirst()
        func local(_ s: String) -> String { Bundle.main.localizedString(forKey: s, value: s, table: nil) }
        return String(localized: "\(local(label)): \(local(outcome))")
    }

    private func run() async {
        running = true
        addresses = localAddresses()
        results = await runChecks()
        running = false
    }
}

/// Poki's log, newest first, with Clear.
struct LogView: View {
    @State private var log = AppLog.shared
    var back: () -> Void
    var body: some View {
        SitePage {
            VStack(spacing: 0) {
                Grabber()
                HStack {
                    SheetHeader(title: Text("Log"), back: "Diagnostics", sideWidth: 110, onBack: back)
                }
                .overlay(alignment: .trailing) {
                    Button { log.clear() } label: { Text("Clear").site(17, line: 22).foregroundStyle(Color(hex: 0xFFC9C5)) }
                        .buttonStyle(.plain).padding(.trailing, 20)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(log.lines.reversed().enumerated()), id: \.offset) { _, line in
                            Text(verbatim: line).mono(12).foregroundStyle(Site.text2).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .textSelection(.enabled)
                    .padding(16)
                    .whiteCard()
                    .padding(.horizontal, 16).padding(.bottom, 40)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
