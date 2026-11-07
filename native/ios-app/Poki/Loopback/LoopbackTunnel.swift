import Foundation
import NetworkExtension

@MainActor
@Observable
final class LoopbackTunnel {
    enum State: Equatable {
        case unavailable, off, connecting, connected, disconnecting
        case failed(String)
    }
    private(set) var state: State = .off {
        didSet { if state != oldValue { AppLog.shared.add("loopback", "local VPN: \(state)") } }
    }
    private(set) var busy = false
    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private var connectionDeadline: Task<Void, Never>?

    // Read the embedded id: signing tools can rewrite bundle identifiers.
    private let providerID: String? = {
        guard let plugins = Bundle.main.builtInPlugInsURL else { return nil }
        return Bundle(url: plugins.appendingPathComponent("PokiTunnel.appex"))?.bundleIdentifier
    }()

    var available: Bool { providerID != nil }
    var connected: Bool { state == .connected }

    init() {
        if !available { state = .unavailable }
        statusObserver = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let connection = notification.object as? NEVPNConnection,
                      connection === self.manager?.connection else { return }
                self.updateStatus()
            }
        }
    }

    isolated deinit {
        connectionDeadline?.cancel()
        if let statusObserver { NotificationCenter.default.removeObserver(statusObserver) }
    }

    func refresh() async {
        #if !targetEnvironment(simulator)
        guard available, !busy else { return }
        busy = true
        defer { busy = false }
        do { manager = try await savedManager(); updateStatus() }
        catch { state = .failed("Cannot read Poki's VPN configuration. Try again, or choose an external connection.") }
        #endif
    }

    /// Called only after the owner chooses Poki's local VPN, never while using an external proxy.
    func connect() async throws {
        #if targetEnvironment(simulator)
        let message = "The local VPN needs a physical iPhone. Its network connection cannot be tested in the Simulator."
        state = .failed(message)
        throw failure(message)
        #else
        guard let providerID else { throw failure("This build has no local VPN. Choose an external connection, or install the build with the local VPN and supported signing.") }
        guard !busy else { throw failure("A local connection change is already in progress. Try again when it finishes.") }
        busy = true
        defer { busy = false }
        do {
            let manager = try await savedManager() ?? NETunnelProviderManager()
            try Task.checkCancellation()
            self.manager = manager
            if manager.connection.status == .connected || manager.connection.status == .connecting || manager.connection.status == .reasserting {
                updateStatus()
                return
            }
            guard manager.connection.status != .disconnecting else { throw failure("The local connection is still stopping. Try again in a moment.") }
            let configuration = NETunnelProviderProtocol()
            configuration.providerBundleIdentifier = providerID
            configuration.serverAddress = "On this iPhone"
            configuration.disconnectOnSleep = false
            configuration.includeAllNetworks = false
            manager.protocolConfiguration = configuration
            manager.localizedDescription = "Poki local connection"
            manager.isEnabled = true
            // Reconnecting requires an explicit Poki action, so another VPN is never displaced on app launch.
            manager.isOnDemandEnabled = false
            state = .connecting
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            try Task.checkCancellation()
            try manager.connection.startVPNTunnel()
            updateStatus()
            connectionDeadline?.cancel()
            connectionDeadline = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                guard let self, self.state == .connecting else { return }
                self.manager?.connection.stopVPNTunnel()
                self.state = .failed("The local VPN did not connect within 15 seconds. Try again, or choose an external connection.")
            }
        } catch is CancellationError {
            updateStatus()
            throw CancellationError()
        } catch {
            let message = "Could not start Poki's local VPN. Allow the VPN configuration when asked. If signing does not include Network Extensions, use the external-connection build with LocalDevVPN or a compatible proxy."
            state = .failed(message)
            throw failure(message)
        }
        #endif
    }

    func disconnect() {
        guard !busy, let manager else { return }
        connectionDeadline?.cancel()
        guard manager.connection.status != .disconnected, manager.connection.status != .invalid else { updateStatus(); return }
        state = .disconnecting
        manager.connection.stopVPNTunnel()
    }

    private func savedManager() async throws -> NETunnelProviderManager? {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        return managers.first { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == providerID }
    }

    private func updateStatus() {
        guard available else { state = .unavailable; return }
        switch manager?.connection.status ?? .invalid {
        case .connected: connectionDeadline?.cancel(); state = .connected
        case .connecting, .reasserting: state = .connecting
        case .disconnecting: state = .disconnecting
        case .invalid, .disconnected:
            if busy && state == .connecting { return }
            connectionDeadline?.cancel()
            if state == .connecting || state == .connected {
                state = .failed("The local VPN disconnected. Reconnect here. If it keeps stopping, check that both Poki and its tunnel were signed with Network Extensions, or choose an external connection.")
            } else if case .failed = state {
                return
            } else { state = .off }
        @unknown default: state = .off
        }
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "PokiLoopback", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
