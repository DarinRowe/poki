import SwiftUI
import UIKit

/// The Debug tab's check of UI automation from Poki's own process (no runner, no port): open the
/// daemon session, tap, type. Every step goes to Poki's log, to the system log (`PokiInProcess`), and
/// to Documents/inprocess-probe.json.
///
/// Launch arguments run it without touching the phone, for a device check from the Mac:
/// `-pokiInProcess self` taps the field below and types into it, then reads it back;
/// `-pokiInProcess later -pokiProbeX 200 -pokiProbeY 300 -pokiProbeDelay 8` waits, then taps that
/// point and types, whatever app is in front by then.
@MainActor
final class InProcessProbe: ObservableObject {
    static let shared = InProcessProbe()
    static let sample = "poki123 AbC 中文24680"

    @Published private(set) var lines: [String] = []
    @Published private(set) var running = false
    @Published var x = "201"
    @Published var y = "437"
    @Published var delay = "8"
    weak var field: UITextField?

    private let queue = DispatchQueue(label: "poki.inprocess.probe", qos: .userInitiated)
    private var record: [[String: Any]] = []

    func startFromLaunchArguments() {
        let defaults = UserDefaults.standard
        guard let mode = defaults.string(forKey: "pokiInProcess") else { return }
        if let v = defaults.string(forKey: "pokiProbeX") { x = v }
        if let v = defaults.string(forKey: "pokiProbeY") { y = v }
        if let v = defaults.string(forKey: "pokiProbeDelay") { delay = v }
        Task {
            // The field has to be on screen for the self test.
            try? await Task.sleep(for: .seconds(1.5))
            switch mode {
            case "self": await selfTest()
            case "later": await later()
            default: await prepareOnly()
            }
        }
    }

    func prepareOnly() async {
        guard begin("prepare") else { return }
        _ = await prepare()
        end()
    }

    /// Taps Poki's own empty field, which focuses it only if the tap arrived, types the sample and
    /// reads the field back.
    func selfTest() async {
        guard begin("self test") else { return }
        defer { end() }
        guard await prepare(), let field else { return }
        field.text = ""
        field.resignFirstResponder()
        try? await Task.sleep(for: .seconds(0.4))
        let frame = field.convert(field.bounds, to: nil)
        let point = CGPoint(x: frame.midX, y: frame.midY)
        let pasteboard = UIPasteboard.general.changeCount
        let tap = await touch([[PKTouchPoint.at(point, offset: 0), PKTouchPoint.at(point, offset: 0.05)]], "tap at [\(Int(point.x)), \(Int(point.y))]")
        try? await Task.sleep(for: .seconds(0.6))
        note("tap landed: field focused = \(field.isFirstResponder)", ["step": "tap_check", "focused": field.isFirstResponder])
        guard tap.delivery == .sent else { return }
        let typed = await type(Self.sample)
        try? await Task.sleep(for: .seconds(0.6))
        let value = field.text ?? ""
        let same = value == Self.sample
        note("read back: \(same ? "same as sent" : "differs (\(value.count) characters)"); clipboard \(UIPasteboard.general.changeCount == pasteboard ? "unchanged" : "changed")",
             ["step": "read_back", "same": same, "characters": value.count, "clipboard_unchanged": UIPasteboard.general.changeCount == pasteboard, "type_delivery": typed.delivery.rawValue])
    }

    /// For another app in front: waits, then taps the point and types the sample there.
    func later() async {
        guard begin("tap and type later") else { return }
        defer { end() }
        guard await prepare() else { return }
        let seconds = Double(delay) ?? 8
        let point = CGPoint(x: Double(x) ?? 201, y: Double(y) ?? 437)
        let background = UIApplication.shared.beginBackgroundTask(withName: "In-process probe")
        defer { UIApplication.shared.endBackgroundTask(background) }
        note("waiting \(Int(seconds)) s; bring the app to try to the front", ["step": "wait", "seconds": seconds])
        try? await Task.sleep(for: .seconds(seconds))
        note("app state: \(UIApplication.shared.applicationState == .active ? "Poki in front" : "Poki in the background")", ["step": "state", "active": UIApplication.shared.applicationState == .active])
        let tap = await touch([[PKTouchPoint.at(point, offset: 0), PKTouchPoint.at(point, offset: 0.05)]], "tap at [\(Int(point.x)), \(Int(point.y))]")
        guard tap.delivery == .sent else { return }
        try? await Task.sleep(for: .seconds(0.8))
        _ = await type(Self.sample)
    }

    // MARK: Steps

    private func prepare() async -> Bool {
        note("prepare: opening the daemon session and Automation Mode", ["step": "prepare_start"])
        let result = await withCheckedContinuation { (c: CheckedContinuation<[String: Any], Never>) in
            queue.async { c.resume(returning: PKInProcess.shared().prepare()) }
        }
        let ok = (result["ok"] as? Bool) == true
        let seconds = String(format: "%.3f", (result["seconds"] as? Double) ?? 0)
        note(ok ? "prepare: ready in \(seconds) s, generation \(result["generation"] ?? "?"), enable \((result["reused"] as? Bool) == true ? "reused" : "new")"
                : "prepare: failed in \(seconds) s: \(result["code"] ?? "?") \(result["detail"] ?? "")",
             result.merging(["step": "prepare"]) { a, _ in a })
        return ok
    }

    private func touch(_ fingers: [[PKTouchPoint]], _ what: String) async -> PKOutcome {
        let outcome = await withCheckedContinuation { (c: CheckedContinuation<PKOutcome, Never>) in
            queue.async { c.resume(returning: PKInProcess.shared().touch(fingers, timeout: 5)) }
        }
        report(what, outcome)
        return outcome
    }

    private func type(_ text: String) async -> PKOutcome {
        let outcome = await withCheckedContinuation { (c: CheckedContinuation<PKOutcome, Never>) in
            queue.async { c.resume(returning: PKInProcess.shared().type(text, timeout: 10)) }
        }
        report("type \(text.count) characters", outcome)
        return outcome
    }

    private func report(_ what: String, _ o: PKOutcome) {
        let delivery = ["not_sent", "sent", "unknown"][o.delivery.rawValue]
        note("\(what): \(delivery) in \(String(format: "%.3f", o.seconds)) s, generation \(o.generation)\(o.code.map { ", \($0)" } ?? "")\(o.detail.map { " (\($0))" } ?? "")",
             ["step": what, "delivery": delivery, "seconds": o.seconds, "generation": o.generation, "code": o.code ?? NSNull()])
    }

    // MARK: Record

    private func begin(_ what: String) -> Bool {
        guard !running else { return false }
        running = true
        record = []
        note("start: \(what)", ["step": "begin", "what": what])
        return true
    }

    private func end() {
        running = false
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let data = try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted]) else { return }
        try? data.write(to: directory.appendingPathComponent("inprocess-probe.json"))
    }

    private func note(_ line: String, _ fields: [String: Any]) {
        var entry = fields
        entry["uptime"] = ProcessInfo.processInfo.systemUptime
        record.append(entry)
        lines.append(line)
        NSLog("PokiInProcess %@", line)
        AppLog.shared.add("inprocess", line)
    }
}

struct InProcessSection: View {
    @ObservedObject var probe = InProcessProbe.shared

    var body: some View {
        Section {
            ProbeField(probe: probe).frame(height: 44)
            HStack {
                Button("Prepare") { Task { await probe.prepareOnly() } }
                Spacer()
                Button("Self test") { Task { await probe.selfTest() } }
            }
            .buttonStyle(.borderless).disabled(probe.running)
            HStack {
                TextField("x", text: $probe.x).keyboardType(.numberPad)
                TextField("y", text: $probe.y).keyboardType(.numberPad)
                TextField("s", text: $probe.delay).keyboardType(.numberPad)
                Button("Later") { Task { await probe.later() } }.buttonStyle(.borderless).disabled(probe.running)
            }
            .monospacedDigit()
            ForEach(probe.lines.indices.reversed(), id: \.self) { i in Text(probe.lines[i]).font(.caption2.monospaced()).textSelection(.enabled) }
        } header: {
            Text("In-process automation")
        } footer: {
            Text("Taps and types from Poki itself, without Poki Runner. Self test taps the field above and types into it. Later waits, then taps the point (x, y) and types, in whatever app is in front.")
        }
    }
}

private struct ProbeField: UIViewRepresentable {
    let probe: InProcessProbe
    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = "In-process test field"
        field.borderStyle = .roundedRect
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.accessibilityIdentifier = "inprocess-field"
        probe.field = field
        return field
    }
    func updateUIView(_ view: UITextField, context: Context) { probe.field = view }
}
