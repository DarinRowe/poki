import Foundation
import PokiCore

/// PokiCore's one transport, with both of Poki's methods behind it. Which one a request goes to is
/// read as the request starts, so a request under way finishes on the method it began with;
/// AppModel changes the method only between tasks (`AutomationChooser`).
final class SwitchingTransport: HTTPTransport, @unchecked Sendable {
    private let xctest: HTTPTransport
    private let native: HTTPTransport?
    private let lock = NSLock()
    private var method: AutomationChooser.Method

    init(xctest: HTTPTransport, native: HTTPTransport?, start: AutomationChooser.Method) {
        self.xctest = xctest
        self.native = native
        method = native == nil ? .xctest : start
    }

    private var current: HTTPTransport {
        lock.lock(); defer { lock.unlock() }
        return method == .native ? (native ?? xctest) : xctest
    }

    /// False when this iPhone has no native services to switch to.
    @discardableResult
    func use(_ new: AutomationChooser.Method) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard new == .xctest || native != nil else { return false }
        method = new
        return true
    }

    var typesThroughKeyboard: Bool { current.typesThroughKeyboard }

    func send(method: String, url: URL, body: Data?, timeout: Double) async throws -> (status: Int, body: Data) {
        try await current.send(method: method, url: url, body: body, timeout: timeout)
    }
}
