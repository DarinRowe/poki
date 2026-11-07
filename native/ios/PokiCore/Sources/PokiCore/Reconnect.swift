import Foundation

/// When Poki's built-in local connection (the packet tunnel) is dialled again after it failed or
/// dropped. It holds the policy and no timers: the app asks `lost()` for the wait before the next try.
public struct ReconnectPlan: Sendable {
    public init() {}

    /// True after the owner ended the connection on purpose (Disconnect, Turn off) until they start it again.
    public private(set) var stoppedByOwner = false

    /// The tunnel is up.
    public mutating func connected(at date: Date = Date()) {}

    /// The tunnel failed or dropped. The seconds to wait before the next try, or nil for no more tries.
    public mutating func lost(at date: Date = Date()) -> Double? { nil }

    public mutating func ownerStopped() {}

    public mutating func ownerStarted() {}

    /// Starts the count again, for a person who opens Poki after the tries ran out.
    public mutating func startOver() {}
}
