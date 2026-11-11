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
                                               options: [.authenticationRequired], icon: UNNotificationActionIcon(systemImageName: "checkmark"))
        let denyAction = UNNotificationAction(identifier: deny, title: String(localized: "Don’t Allow"),
                                              options: [.destructive], icon: UNNotificationActionIcon(systemImageName: "xmark"))
        let approvals = UNNotificationCategory(identifier: category, actions: [allowAction, denyAction], intentIdentifiers: [],
                                               options: [.hiddenPreviewsShowTitle])
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([approvals, ChatReplyNotice.category])
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

    // The completion-handler forms, answered on the main thread. The async forms finish on another
    // thread, and iOS stops the app for that when a tap on a notification is what opened it.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content
        let category = content.categoryIdentifier
        let action = response.actionIdentifier
        let typed = (response as? UNTextInputNotificationResponse)?.userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let approval = content.userInfo["approval"] as? String
        Task { @MainActor in
            if category == ChatReplyNotice.categoryID {
                // Typed on the notification: the chat goes on from where the owner is. A plain tap opens Poki.
                if action == ChatReplyNotice.replyAction, let typed, !typed.isEmpty { ChatReplyNotice.answer(typed) }
            } else if let approval, action == ApprovalNotice.allow || action == ApprovalNotice.deny {
                ApprovalIntentBridge.submit(ApprovalDecision(approvalID: approval, approved: action == ApprovalNotice.allow))
            }
            completionHandler()
        }
    }

    /// While Poki is open the banner still shows, so the buttons are there too.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

/// Poki's reply at the end of a chat task, when Poki is not in front: the owner reads it where they
/// are and can answer on the notification itself (touch and hold it, or pull it down, for Reply), and
/// the chat carries on from there. A tap opens Poki.
enum ChatReplyNotice {
    static let categoryID = "chat.reply"
    static let replyAction = "chat.reply.text"
    static let id = "chat-reply"

    static var category: UNNotificationCategory {
        let reply = UNTextInputNotificationAction(identifier: replyAction, title: String(localized: "Reply"), options: [],
                                                  icon: UNNotificationActionIcon(systemImageName: "arrowshape.turn.up.left"),
                                                  textInputButtonTitle: String(localized: "Send"),
                                                  textInputPlaceholder: String(localized: "Message Poki"))
        return UNNotificationCategory(identifier: categoryID, actions: [reply], intentIdentifiers: [], options: [])
    }

    @MainActor static func post(_ text: String, session: String) {
        let content = UNMutableNotificationContent()
        content.title = "Poki"
        content.body = String(text.prefix(400))
        content.categoryIdentifier = categoryID
        content.userInfo = ["chat": session]
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = "chat"
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    @MainActor static func clear() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }

    /// The owner's words from the notification, into the chat as if typed there.
    @MainActor static func answer(_ text: String) {
        guard let chat = AskPoki.chat else { return }
        AppLog.shared.add("chat", "reply from the notification")
        // After a turn that ended on a problem the conversation carries on with the new words; a
        // task still under way takes none (send would drop them without a word).
        guard !chat.running else {
            AttentionNotice.post(title: "Poki", body: String(localized: "Poki is still working. Send that again when it is done."))
            return
        }
        chat.send(text)
    }
}

/// Thanks for the star, a moment after GitHub opened (Setup › Contribute).
enum ThanksNotice {
    static func post() {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Thank You for Supporting Poki")
        content.body = String(localized: "A star helps other people find Poki. Thank you for being part of it.")
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 4, repeats: false)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["thanks-star"])
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "thanks-star", content: content, trigger: trigger))
    }
}

/// The notification for a sign-in from a client outside the relay's known list. A tap opens Poki,
/// where the owner answers (Allow asks for Face ID or the passcode on the alert's own button).
enum ConnectionNotice {
    @MainActor static func post(_ ask: AppModel.ConnectionAsk) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Allow \(ask.client) to connect?")
        content.body = String(localized: "A client Poki doesn’t know (\(ask.callback)) is signing in with \(ask.connector). Open Poki to allow or deny it.")
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = "connections"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "connection-\(ask.id)", content: content, trigger: nil))
    }

    @MainActor static func clear(_ ask: AppModel.ConnectionAsk) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["connection-\(ask.id)"])
    }
}

/// The pairing code as a time-sensitive banner, so it shows over Settings' Pair with Poki screen.
enum PairingNotice {
    static let id = "pairing-code"
    @MainActor static func post(pin: String) {
        let content = UNMutableNotificationContent()
        let shown = pin.count == 6 ? "\(pin.prefix(3)) \(pin.suffix(3))" : pin
        content.title = String(localized: "Pairing code \(shown)")
        content.body = String(localized: "Type it on the Pair with Poki screen in Settings.")
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
    @MainActor static func clear() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }
}

/// What the Live Activity would pop up for (the agent's hand-off, a problem) when there is no Live
/// Activity to pop up: dismissed, off in Settings, or Poki turned on from the background, where iOS does
/// not let an app start one. A time-sensitive banner instead.
enum AttentionNotice {
    static let id = "poki-attention"
    @MainActor static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
    @MainActor static func clear() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }
}
