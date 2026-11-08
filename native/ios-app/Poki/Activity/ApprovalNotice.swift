import Foundation
import UserNotifications

/// A time-sensitive notification for each approval, so the person hears about it even when the Live
/// Activity is off, dismissed or hidden (and, before iOS 26, as the way to answer it). Touch and hold
/// it for Allow (Face ID or the passcode first) and Don't Allow. PokiCore sends no input while an
/// approval waits, so only the person can press them.
enum ApprovalNotice {
    static let category = "approval"
    static let allow = "approval.allow"
    static let deny = "approval.deny"

    /// Allow and Don't Allow on the notification itself (touch and hold it, or pull it down), so an
    /// approval can be answered without opening Poki. Allow asks for Face ID or the passcode first.
    @MainActor static func registerActions() {
        let allowAction = UNNotificationAction(identifier: allow, title: String(localized: "Allow"),
                                               options: [.authenticationRequired], icon: UNNotificationActionIcon(systemImageName: "faceid"))
        let denyAction = UNNotificationAction(identifier: deny, title: String(localized: "Don’t Allow"),
                                              options: [.destructive], icon: UNNotificationActionIcon(systemImageName: "xmark"))
        let approvals = UNNotificationCategory(identifier: category, actions: [allowAction, denyAction], intentIdentifiers: [],
                                               options: [.hiddenPreviewsShowTitle])
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([approvals])
        center.delegate = ApprovalNoticeDelegate.shared
    }

    static func requestPermission() {
        Task { @MainActor in registerActions() }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in AppLog.shared.add("notice", granted ? "notifications allowed" : "notifications not allowed") }
        }
    }

    static func post(_ approval: PendingApproval, caller: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = caller.map { String(localized: "\($0) needs your OK") } ?? String(localized: "Poki needs your OK")
        content.body = String(localized: "\(approval.summary) in \(approval.app). Touch and hold to allow or deny.")
        content.categoryIdentifier = category
        content.userInfo = ["approval": approval.id]
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = "approvals"
        let request = UNNotificationRequest(identifier: "approval-\(approval.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func clear(_ id: String) {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: ["approval-\(id)"])
        center.removePendingNotificationRequests(withIdentifiers: ["approval-\(id)"])
    }
}

/// Answers from the notification's buttons go the same way as the Live Activity's (ApprovalIntentBridge).
final class ApprovalNoticeDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = ApprovalNoticeDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo["approval"] as? String else { return }
        let action = response.actionIdentifier
        guard action == ApprovalNotice.allow || action == ApprovalNotice.deny else { return }
        await MainActor.run { ApprovalIntentBridge.submit(ApprovalDecision(approvalID: id, approved: action == ApprovalNotice.allow)) }
    }

    /// While Poki is open the banner still shows, so the buttons are there too.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
