// Allow and Deny on the Live Activity. The bridge and the two LiveActivityIntents are ported from
// AgentApprovalIntents.swift in Clarklevis1995/dsh-mobile (commit ebe19764,
// DeepSeekHarnessMobile/LiveActivity/AgentApprovalIntents.swift), MIT License, Copyright (c) 2026
// Chaofan Li. Poki keys a decision by its approval id alone and keeps an App Group mailbox for an
// intent that runs outside the app. See THIRD_PARTY_NOTICES.md.
import AppIntents
import Foundation

struct ApprovalDecision: Hashable, Sendable {
    let approvalID: String
    let approved: Bool
}

/// A LiveActivityIntent runs in the app's process, so the button hands its decision straight to
/// AppModel through this bridge, which holds no state of its own. In the widget's process, or before
/// AppModel installed itself, the bridge has no handler and the decision goes through the mailbox.
@MainActor
enum ApprovalIntentBridge {
    typealias Handler = @MainActor @Sendable (ApprovalDecision) -> Bool

    private static var handler: Handler?

    static func install(_ handler: @escaping Handler) {
        self.handler = handler
    }

    static func submit(_ decision: ApprovalDecision) -> Bool {
        handler?(decision) ?? false
    }
}

/// PokiCore sends no input at all while an approval is pending, so the automation cannot press this
/// button itself. Allow asks for Face ID or the passcode first.
struct ApproveActionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Allow action"
    static let description = IntentDescription("Lets the agent do the step that is waiting for you.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let isDiscoverable = false

    @Parameter(title: "Approval") var approvalID: String

    init() {}
    init(approvalID: String) { self.approvalID = approvalID }

    @MainActor
    func perform() async throws -> some IntentResult {
        let decision = ApprovalDecision(approvalID: approvalID, approved: true)
        if !ApprovalIntentBridge.submit(decision) { ApprovalMailbox.post(decision) }
        return .result()
    }
}

/// Deny needs no authentication: refusing a step is always safe, like Stop.
struct DenyActionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Deny action"
    static let description = IntentDescription("Refuses the step that is waiting for you.")
    static let isDiscoverable = false

    @Parameter(title: "Approval") var approvalID: String

    init() {}
    init(approvalID: String) { self.approvalID = approvalID }

    @MainActor
    func perform() async throws -> some IntentResult {
        let decision = ApprovalDecision(approvalID: approvalID, approved: false)
        if !ApprovalIntentBridge.submit(decision) { ApprovalMailbox.post(decision) }
        return .result()
    }
}

/// Stop runner on the Live Activity: stops the runner (and with it iOS's automation banner) until an
/// agent's next request. No authentication: stopping is always safe.
struct StopRunnerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop runner"
    static let isDiscoverable = false
    init() {}
    func perform() async throws -> some IntentResult {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(ApprovalMailbox.stopRunner as CFString), nil, nil, true)
        return .result()
    }
}

/// Decisions in flight between an intent that ran outside the app and the app: written to the App
/// Group and announced with a Darwin notification.
enum ApprovalMailbox {
    static let notification = "nz.zheha.poki.approval"
    static let stopRunner = "nz.zheha.poki.stop-runner"
    private static let key = "approval.decisions"

    static func post(_ decision: ApprovalDecision) {
        var decisions = SharedContainer.defaults.dictionary(forKey: key) as? [String: Bool] ?? [:]
        decisions[decision.approvalID] = decision.approved
        SharedContainer.defaults.set(decisions, forKey: key)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(notification as CFString), nil, nil, true)
    }

    /// Takes every decision posted so far, once.
    static func drain() -> [ApprovalDecision] {
        let decisions = SharedContainer.defaults.dictionary(forKey: key) as? [String: Bool] ?? [:]
        SharedContainer.defaults.removeObject(forKey: key)
        return decisions.map { ApprovalDecision(approvalID: $0.key, approved: $0.value) }
    }
}
