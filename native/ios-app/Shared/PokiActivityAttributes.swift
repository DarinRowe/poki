// The Live Activity's shared data. Phase layout and the terminal flag follow AgentActivityAttributes.swift
// from Clarklevis1995/dsh-mobile (commit ebe19764, DeepSeekHarnessMobile/LiveActivity/AgentActivityAttributes.swift),
// MIT License, Copyright (c) 2026 Chaofan Li. See THIRD_PARTY_NOTICES.md.
import ActivityKit
import Foundation

/// The Live Activity's data, shared by the app (which starts and updates it) and the widget extension
/// (which draws it). ActivityKit caps the payload at 4 KB, so the screenshot thumbnail is not in it:
/// the app writes it to the App Group container and the state carries only its version.
struct PokiActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// `done` is set by ActivityController itself when the agent has been quiet for a while after a
        /// run of steps; `deciding` by AppModel the moment Allow or Deny is tapped on the Live Activity,
        /// until PokiCore has the answer.
        enum Phase: String, Codable, Hashable {
            case idle, working, approval, deciding, pairing, setup, problem, done

            /// The phases a person has to answer: a step from the agent never replaces them.
            var holdsApproval: Bool { self == .approval || self == .deciding }
        }
        var phase: Phase
        /// What the agent is doing, in a few words ("Tap “Send”"), or the phase's line, in English: the
        /// face words it in the system's language (ActivityWords).
        var headline: String
        /// The status word in place of the phase's own ("Runner Stopped").
        var label: String?
        /// The app in front.
        var app: String?
        /// Bumped whenever a new thumbnail is written to the App Group container.
        var thumbnailVersion: Int
        /// A pending approval, if any. Its buttons are App Intents; see ApprovalIntents.swift.
        var approval: PendingApproval?
        /// While `deciding`: true for Allow, false for Deny.
        var decision: Bool?
        /// The pairing PIN while on-device pairing is waiting for it.
        var pin: String?
        /// The runner is stopped while no agent uses the phone (no automation banner); the next
        /// request starts it again.
        var runnerPaused = false
        /// Whether each of the run's latest steps went through, newest last, at most `outcomeLimit`.
        var outcomes: [Bool] = []
        /// During setup: which step the person is on ("2/6").
        var guide: Guide?
        /// When the agent's current run of steps began.
        var since: Date?
        /// Steps in the current run, and how many of them did not go through. Kept by ActivityController.
        var stepCount = 0
        var failedCount = 0
        /// When the run finished (phase `done`), so the summary shows a fixed duration.
        var endedAt: Date?
        /// A short-lived event ("Started", "Now in WeChat", "Allowed") shown as the status word for a few
        /// seconds. ActivityController clears it.
        var event: Event?

        static let outcomeLimit = 12
    }
    struct Event: Codable, Hashable {
        enum Kind: String, Codable, Hashable { case started, app, finished, approved, denied, expired, problem, paired, code }
        var kind: Kind
        var text: String
    }
    struct Guide: Codable, Hashable {
        var number: Int
        var count: Int
        var title: String
    }
    var deviceName: String
}

struct PendingApproval: Codable, Hashable {
    var id: String
    var app: String
    var summary: String
    /// Why it needs the owner, from PokiCore's rules: `sending a message ("send")`, `a payment ("pay")`.
    var reason: String
    var expires: Date

    /// The approval as a short question, from PokiCore's reason and the app: "Send in Messages?".
    /// The summary ("Tap “Send”") says how, which the thumbnail shows better.
    var question: String {
        // PokiCore names the app, or says "unknown", or describes the home screen at length.
        let place = app.isEmpty || app == "unknown" || app.contains("(") ? nil : app
        if reason.hasPrefix("sending") { return place.map { String(activity: "Send in \($0)?") } ?? String(activity: "Send a message?") }
        if reason.hasPrefix("a payment") { return place.map { String(activity: "Pay in \($0)?") } ?? String(activity: "Make a payment?") }
        if reason.hasPrefix("deleting") { return place.map { String(activity: "Delete in \($0)?") } ?? String(activity: "Delete this?") }
        if reason.hasPrefix("typing into a password") { return String(activity: "Type a password?") }
        if reason.hasPrefix("input in"), let place { return String(activity: "Use \(place)?") }
        return String(activity: "Allow this step?")
    }
}

enum SharedContainer {
    static let appGroup = "group.nz.zheha.poki"
    static var url: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) }
    static var thumbnailURL: URL? { url?.appendingPathComponent("activity-thumbnail.jpg") }
    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }
}
