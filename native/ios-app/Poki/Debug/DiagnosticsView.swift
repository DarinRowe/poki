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
        Form {
            Section {
                Button(copied ? "Copied" : "Copy Log", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.string = log.text
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(2)); copied = false }
                }
                ShareLink(item: log.text, subject: Text("Poki log")) { Label("Share Log", systemImage: "square.and.arrow.up") }
                Button { path.append(.log) } label: {
                    LabeledContent("Log") { Text("\(log.lines.count) lines") }
                }
                .foregroundStyle(Color(.label))
                Button { path.append(.activityPreview) } label: { LabeledContent("Live Activity Preview") { EmptyView() } }
                    .foregroundStyle(Color(.label))
            } header: {
                Text("Log")
            } footer: {
                Text("Runner starts and stops, agent steps, approvals, and connection changes. Password field entries are never logged.")
            }
            // The in-process path's switch and probes (ESP-173, ESP-175).
            InProcessSection()
            Section {
                if let loop = loopbackInterface(addresses) {
                    Text(verbatim: "\(loop.interface)  \(loop.address)").font(.body.monospaced().weight(.semibold))
                    Text(loop.ipv6.isEmpty ? "No IPv6 on this interface" : "IPv6 present: \(loop.ipv6.joined(separator: ", "))")
                        .font(.footnote.monospaced()).foregroundStyle(loop.ipv6.isEmpty ? Color.secondary : Color.red)
                } else {
                    Text("No interface has a 10.7.0.x address. Check that your proxy app is on and its loopback module is enabled.")
                }
            } header: {
                Text("Proxy Loopback Interface")
            } footer: {
                Text(verbatim: "Network path: \(model.loopback.pathSummary). Wi-Fi \(model.loopback.wifiUp ? "up" : "down"), cellular \(model.loopback.cellularUp ? "up" : "down")\(model.loopback.cellularOnly ? " (cellular only)" : "")")
                    .textSelection(.enabled)
            }
            .textSelection(.enabled)
            Section("Checks") {
                ForEach(results) { r in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Self.title(r)).font(.subheadline.weight(.semibold))
                        Text(verbatim: "\(r.target)  \(r.milliseconds) ms").font(.caption.monospaced()).foregroundStyle(Color(.secondaryLabel))
                        if !r.detail.isEmpty { Text(verbatim: r.detail).font(.caption.monospaced()) }
                        if !r.firstBytes.isEmpty { Text(verbatim: "first bytes: \(r.firstBytes)").font(.caption.monospaced()) }
                    }
                    .textSelection(.enabled)
                }
                Button(running ? "Running…" : "Run Checks") { Task { await run() } }.disabled(running)
            }
            Section {
                LabeledContent("Port on 10.7.0.1") {
                    TextField(text: $hold.port, prompt: Text(verbatim: "49152")) { Text("Port on 10.7.0.1") }
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).monospacedDigit()
                }
                Picker("Experiment", selection: $hold.experiment) {
                    ForEach(Hold.Experiment.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                }
                .disabled(hold.holding)
                Button("Start Hold") { hold.start() }.disabled(hold.holding)
                Button("Stop", role: .destructive) { hold.stop() }.disabled(!hold.holding)
                if !hold.log.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(hold.log.indices, id: \.self) { i in Text(verbatim: hold.log[i]).font(.caption2.monospaced()) }
                    }
                    .textSelection(.enabled)
                }
            } header: {
                Text("Background Hold")
            } footer: {
                Text("Tap Start, leave the app for a while, then return. The log records suspension gaps and connection closures.")
            }
            Section("Addresses") {
                ForEach(addresses.indices, id: \.self) { i in
                    Text(verbatim: "\(addresses[i].interface)  \(addresses[i].address)").font(.caption.monospaced())
                }
            }
            .textSelection(.enabled)
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .task { await run() }
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
        List {
            ForEach(Array(log.lines.reversed().enumerated()), id: \.offset) { _, line in
                Text(verbatim: line).font(.caption.monospaced()).textSelection(.enabled)
            }
        }
        .listStyle(.plain)
        .overlay { if log.lines.isEmpty { ContentUnavailableView("No Log Yet", systemImage: "doc.text") } }
        .navigationTitle("Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear", role: .destructive) { log.clear() }
            }
        }
    }
}
