import Foundation
import Network

/// Live loopback status: every few seconds while Poki is in front (and on demand), a TCP connect to
/// developer services at 10.7.0.1, which only answer when Poki or an external VPN reflects
/// 10.7.0.1 back to this phone. Also whether Wi-Fi is up, which the phone's developer services need.
@MainActor
@Observable
final class LoopbackMonitor {
    enum State: Equatable {
        case checking
        case working(ms: Int)
        /// A tunnel gave the phone a 10.7.0.x address, but nothing answered through it.
        case noAnswer
        case off
    }
    private(set) var state = State.checking
    private(set) var onWiFi = false
    private(set) var checkedAt: Date?
    /// When the loopback last stopped answering after it had worked; nil while it works.
    private(set) var droppedAt: Date?
    /// Called on every change of state, with the old and the new one.
    var onChange: ((State, State) -> Void)?
    private var timer: Timer?
    private let path = NWPathMonitor()
    private var running = false

    init() {
        path.pathUpdateHandler = { [weak self] path in
            let wifi = path.status == .satisfied && path.usesInterfaceType(.wifi)
            Task { @MainActor in
                guard let self else { return }
                if self.onWiFi != wifi { self.onWiFi = wifi; self.check() }
            }
        }
        path.start(queue: DispatchQueue(label: "poki.path"))
    }

    private static func same(_ a: State, _ b: State) -> Bool {
        switch (a, b) {
        case (.working(let x), .working(let y)): abs(x - y) < 100
        default: a == b
        }
    }

    var isWorking: Bool { if case .working = state { true } else { false } }

    /// Checks every `interval` seconds until `pause` (3 s in front; the app uses a slower one in the
    /// background while an agent works, so a dropped tunnel is noticed and named).
    func resume(every interval: TimeInterval = 3) {
        if let timer, abs(timer.timeInterval - interval) < 0.5 { return }
        timer?.invalidate()
        check()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in Task { @MainActor in self?.check() } }
    }

    func pause() { timer?.invalidate(); timer = nil }

    func check() {
        guard !running else { return }
        running = true
        Task {
            var result = await probe(label: "loopback", host: "10.7.0.1", port: 49152, timeout: 1.5)
            if result.outcome != "connected" {
                result = await probe(label: "loopback", host: "10.7.0.1", port: 62078, timeout: 1.5)
            }
            running = false
            let next: State = result.outcome == "connected" ? .working(ms: result.milliseconds) : loopbackInterface() == nil ? .off : .noAnswer
            // Only a change is published, so the screens are not redrawn every 3 s (a redraw while
            // the person drags a list makes scrolling stutter).
            if !Self.same(next, state) {
                let old = state
                state = next; checkedAt = Date()
                if case .working = old, !isWorking { droppedAt = Date() }
                if isWorking { droppedAt = nil }
                AppLog.shared.add("loopback", "developer service: \(next)")
                onChange?(old, next)
            }
        }
    }

    var text: String {
        switch state {
        case .checking: String(localized: "Checking…")
        case .working: String(localized: "Working")
        case .noAnswer: String(localized: "Tunnel on, no answer")
        case .off: String(localized: "Off")
        }
    }

    var detail: String {
        switch state {
        case .checking: String(localized: "Looking for this iPhone at 10.7.0.1.")
        case .working(let ms): String(localized: "This iPhone answers at 10.7.0.1 (\(ms) ms).") + (onWiFi ? "" : " " + String(localized: "Connect to Wi-Fi: the developer services need it."))
        case .noAnswer: String(localized: "The local interface is present, but this iPhone's developer services do not answer. Check Developer Mode and Wi-Fi, then reconnect the local connection.")
        case .off: String(localized: "This iPhone does not answer yet. Enable Poki's local connection, or choose an external connection in Setup.")
        }
    }
}
