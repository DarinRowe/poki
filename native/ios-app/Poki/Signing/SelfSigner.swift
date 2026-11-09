import Foundation
import UIKit
import UserNotifications

/// Poki keeps its own signing, the way Poki Setup does on a computer (PokiLauncher's signer, which is
/// Poki Setup's Rust core): the Apple Account is signed in here, with anisette from a remote server,
/// the next build is signed ahead of time (the installed copy for a refresh, the chosen channel's
/// release for an update), and it is installed over the loopback only when the person taps Install
/// and no task is running, because iOS ends Poki when the new copy lands.
///
/// Secrets (the Apple session, the kept password, the team key, the anisette identity) live only in
/// the Keychain, after first unlock, on this device.
@MainActor
@Observable
final class SelfSigner {
    struct Channel: Decodable, Hashable, Identifiable {
        let id: String
        let title: String
    }

    struct Status: Decodable, Equatable {
        var signed_in: Bool
        var needs_code: Bool
        var apple_id: String?
        var name: String?
        var team_id: String?
        var keeps_password: Bool
        var anisette: String
        var channel: String
        var channels: [Channel]
    }

    struct Team: Decodable, Identifiable, Hashable {
        let team_id: String
        let name: String
        let kind: String
        let is_free: Bool
        var id: String { team_id }
    }

    struct Prepared: Decodable, Equatable {
        let kind: String
        let ipa: String
        let bundle_id: String
        let version: String
        let build: String
        let tag: String
        let team_name: String
        let team_is_free: Bool
        let profile_expires_at: Int64
        let prepared_at: Int64
        var expires: Date { Date(timeIntervalSince1970: TimeInterval(profile_expires_at)) }
        var title: String { kind == "update" ? "Poki \(version) (\(build))" : "Refreshed Poki \(version) (\(build))" }
    }

    struct Release: Decodable, Equatable {
        let tag: String
        let version: String
        let build: String
        let channel: String
    }

    /// Prepare a fresh build when the installed profile has this many days left or fewer.
    static let refreshWithDaysLeft: Double = 3
    /// Home warns, and a notification reminds once a day, when the installed profile has this many days left.
    static let warnWithDaysLeft: Double = 2

    private(set) var status: Status?
    private(set) var teams: [Team] = []
    private(set) var ready: [String: Prepared] = [:]
    private(set) var latest: Release?
    /// What the signer is doing now, for the Setup page.
    private(set) var working: String?
    private(set) var fraction: Double?
    private(set) var lastError: String?
    private(set) var lastCheck: Date?
    /// When the installed Poki stops opening: its own profile's expiry. Nil when it has none (simulator).
    let expiry: Date? = SelfSigner.installedProfileExpiry() ?? SelfSigner.screenshotExpiry
    let installedVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    let installedBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""

    /// The phone's own services (10.7.0.1 and the pairing file), when the loopback answers.
    var phone: () -> [String: Any]? = { nil }
    /// No task is running, so Poki may be ended by an install.
    var isIdle: () -> Bool = { false }
    /// Why an install waits, for the message under the button.
    var busyReason: () -> String? = { nil }
    /// Before an install the owner asked for: Poki winds down (automation session, Live Activity)
    /// so it exits cleanly when iOS replaces it, and comes back on after.
    var beforeInstall: () -> Void = {}

    private var started = false
    private var timer: Timer?
    private let log = AppLog.shared

    var signedIn: Bool { status?.signed_in == true }
    var needsCode: Bool { status?.needs_code == true }
    var daysLeft: Double? { expiry.map { $0.timeIntervalSinceNow / 86_400 } }
    /// The build Install would put on: an update when one is ready, else a refresh.
    var next: Prepared? { ready["update"] ?? ready["refresh"] }
    var channelTitle: String { status?.channels.first { $0.id == status?.channel }?.title ?? status?.channel ?? "" }

    static var home: URL {
        let url = AppFiles.support.appendingPathComponent("signer", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Where Poki Setup leaves its team key for Poki (see the desktop core's signing-identity.json).
    static var handedIdentity: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("PokiSetup/signing-identity.json")
    }

    func start() {
        guard !started else { return }
        started = true
        SignerBridge.installVault()
        Task {
            do {
                _ = try await SignerBridge.call(["op": "configure", "home": Self.home.path, "device_name": UIDevice.current.name])
                if let imported = try? await SignerBridge.decode([String: AnyDecodable].self, ["op": "import_identity", "path": Self.handedIdentity.path]),
                   imported["imported"]?.value as? Bool == true {
                    log.add("signing", "took Poki Setup's signing key into the Keychain")
                }
                await reload()
                loadReady()
                maintain()
            } catch {
                lastError = error.localizedDescription
                log.add("signing", "signer did not start: \(error.localizedDescription)")
            }
        }
        // Poki stays up in the background while it is on; a check every three hours is plenty for
        // a 7-day profile.
        timer = Timer.scheduledTimer(withTimeInterval: 3 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.maintain() }
        }
    }

    func reload() async {
        do { status = try await SignerBridge.decode(Status.self, ["op": "status"]) } catch { lastError = error.localizedDescription }
    }

    // MARK: Account

    func signIn(appleID: String, password: String, keepPassword: Bool) async {
        await run("Signing in") {
            _ = try await SignerBridge.call(["op": "sign_in", "apple_id": appleID, "password": password, "keep_password": keepPassword])
        }
        await reload()
        if signedIn { await loadTeams() }
    }

    func finishSignIn(code: String) async {
        await run("Checking the code") { _ = try await SignerBridge.call(["op": "finish_sign_in", "code": code]) }
        await reload()
        if signedIn { await loadTeams() }
    }

    func signOut() async {
        await run("Signing out") { _ = try await SignerBridge.call(["op": "sign_out"]) }
        teams = []
        await reload()
    }

    func loadTeams() async {
        do { teams = try await SignerBridge.decode([Team].self, ["op": "teams"]) } catch { lastError = error.localizedDescription }
        await reload()
    }

    func choose(team: Team) async {
        await run("Choosing the team") { _ = try await SignerBridge.call(["op": "choose_team", "team_id": team.team_id]) }
        await reload()
    }

    func setChannel(_ id: String) async {
        await run(nil) { _ = try await SignerBridge.call(["op": "set_channel", "channel": id]) }
        await reload()
        latest = nil
        maintain()
    }

    func setAnisette(_ url: String) async {
        await run(nil) { _ = try await SignerBridge.call(["op": "set_anisette", "url": url]) }
        await reload()
    }

    // MARK: Builds

    private func loadReady() {
        var found: [String: Prepared] = [:]
        for kind in ["refresh", "update"] {
            let url = Self.home.appendingPathComponent("ready/\(kind)/manifest.json")
            if let data = try? Data(contentsOf: url), let p = try? JSONDecoder().decode(Prepared.self, from: data), FileManager.default.fileExists(atPath: p.ipa) {
                found[kind] = p
            }
        }
        // A build that is already on (its build number is installed) has nothing left to give.
        if let u = found["update"], u.build == installedBuild, u.version == installedVersion { found["update"] = nil }
        if let r = found["refresh"], let expiry, r.expires <= expiry.addingTimeInterval(3600) { found["refresh"] = nil }
        ready = found
    }

    /// Prepares what is due, by itself: an update when the channel has a newer Poki, a refresh when
    /// the installed profile is close to expiring. Never installs.
    func maintain() {
        guard signedIn, working == nil, phone() != nil else { return }
        Task {
            lastCheck = Date()
            if let rel = try? await SignerBridge.decode(Release.self, ["op": "check_update"]) {
                latest = rel
                if isNewer(rel), ready["update"]?.tag != rel.tag {
                    await prepare(kind: "update")
                    return
                }
            }
            if let days = daysLeft, days <= Self.refreshWithDaysLeft, ready["refresh"] == nil, ready["update"] == nil {
                await prepare(kind: "refresh")
            }
            remindIfExpiring()
        }
    }

    /// Looks up the newest build on the chosen channel without preparing it, for the version rows.
    /// Works without an Apple Account. False when GitHub could not be read.
    @discardableResult
    func checkLatest() async -> Bool {
        guard let rel = try? await SignerBridge.decode(Release.self, ["op": "check_update"]) else { return false }
        latest = rel
        lastCheck = Date()
        return true
    }

    func isNewer(_ rel: Release) -> Bool {
        let installed = (installedVersion, Int(installedBuild) ?? 0)
        switch rel.version.compare(installed.0, options: .numeric) {
        case .orderedDescending: return true
        case .orderedAscending: return false
        case .orderedSame: return (Int(rel.build) ?? 0) > installed.1
        }
    }

    func prepare(kind: String) async {
        guard var request = phone() else {
            lastError = String(localized: "Poki can't reach this iPhone. Turn on the loopback, then try again.")
            return
        }
        request["op"] = "prepare"
        request["kind"] = kind
        request["app_path"] = Bundle.main.bundlePath
        request["device_name"] = UIDevice.current.name
        await run(kind == "update" ? "Preparing the update" : "Preparing a refresh") {
            let p = try await SignerBridge.decode(Prepared.self, request) { [weak self] progress in
                Task { @MainActor in self?.show(progress) }
            }
            self.ready[kind] = p
            self.log.add("signing", "prepared \(kind): \(p.version) (\(p.build)), profile until \(p.expires)")
            self.notify(title: kind == "update" ? String(localized: "Poki Update Ready") : String(localized: "Poki Refresh Ready"),
                        body: String(localized: "Open Setup and tap Install when Poki isn't running a task."))
        }
    }

    /// Installs the prepared build. iOS ends Poki when it lands; a notification brings it back.
    func install() async {
        guard let p = next else { log.add("signing", "install tapped, but no build is ready"); return }
        log.add("signing", "install tapped: \(p.kind) \(p.version) (\(p.build))")
        guard isIdle() else {
            let why = busyReason() ?? ""
            lastError = String(localized: "Poki is running a task. Install when it has finished.") + (why.isEmpty ? "" : " " + why)
            log.add("signing", "install waits: \(why)")
            return
        }
        guard var request = phone() else {
            lastError = String(localized: "Poki can't reach this iPhone. Turn on the loopback, then try again.")
            log.add("signing", "install: no loopback or pairing file")
            return
        }
        request["op"] = "install"
        request["manifest"] = Self.home.appendingPathComponent("ready/\(p.kind)/manifest.json").path
        let reopen = "nz.zheha.poki.signing.reopen"
        scheduleReopenNotice(id: reopen)
        beforeInstall()
        steppedAside = false
        installFraction = nil
        // iOS holds the last part of an upgrade until the app it replaces leaves the screen: Poki
        // steps aside to the Home Screen by itself once the new copy is almost in (or has stalled
        // there), keeping a background task so the request can finish; iOS then ends Poki, and the
        // notice above reopens it.
        let background = UIApplication.shared.beginBackgroundTask(withName: "Poki update")
        let watch = Task { @MainActor [weak self] in
            var last: (fraction: Double, since: Date)?
            while !Task.isCancelled, let self, self.working != nil {
                try? await Task.sleep(for: .seconds(1))
                guard let f = self.installFraction else { continue }
                if last?.fraction != f { last = (f, Date()) }
                if f >= 0.9 || (f >= 0.4 && Date().timeIntervalSince(last!.since) > 5) { self.stepAside(); break }
            }
        }
        await run("Installing") {
            _ = try await SignerBridge.call(request) { [weak self] progress in
                Task { @MainActor in self?.show(progress) }
            }
        }
        watch.cancel()
        UIApplication.shared.endBackgroundTask(background)
        // Still here: iOS did not end Poki (or the install failed).
        if lastError != nil { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reopen]) }
    }

    // MARK: Helpers

    private func run(_ title: String?, _ work: () async throws -> Void) async {
        working = title
        fraction = nil
        lastError = nil
        defer { working = nil; fraction = nil }
        do { try await work() } catch {
            lastError = error.localizedDescription
            log.add("signing", "\(title ?? "signer"): \(error.localizedDescription)")
        }
    }

    /// The upgrade's progress while it installs, for `install`'s watch.
    private var installFraction: Double?
    private var steppedAside = false

    /// Poki to the Home Screen, as the person swiping up would: iOS finishes the upgrade only once the
    /// app it replaces is no longer in front. Once per install.
    private func stepAside() {
        guard !steppedAside, UIApplication.shared.applicationState == .active else { return }
        steppedAside = true
        working = String(localized: "Finishing the update: close Poki and swipe it away in the app switcher")
        // The last step: the owner is told Poki must exit, and how to finish (the alert's OK steps
        // aside); the notice says it again in case the alert was missed.
        finishNotice = true
        notify(title: String(localized: "Close Poki to Finish the Update"),
               body: String(localized: "Swipe up to the app switcher and swipe Poki away, then open it again."))
    }
    /// The last install step's alert: Poki has to exit for the update to finish.
    var finishNotice = false
    /// OK on that alert: Poki leaves for the Home Screen.
    func finishNoticeAnswered() {
        finishNotice = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            UIApplication.shared.perform(NSSelectorFromString("suspend"))
        }
    }

    private func show(_ progress: [String: Any]) {
        switch progress["kind"] as? String {
        case "step": working = progress["title"] as? String ?? working; fraction = nil
        case "part":
            fraction = progress["fraction"] as? Double
            if progress["id"] as? String == "install" { installFraction = fraction }
            if let d = progress["detail"] as? String { working = d }
        case "note", "waiting": if let t = progress["text"] as? String { working = t }
        default: break
        }
    }

    private func notify(title: String, body: String, id: String = UUID().uuidString, after seconds: TimeInterval? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = ["poki_link": "poki://setup"]
        let trigger = seconds.map { UNTimeIntervalNotificationTrigger(timeInterval: $0, repeats: false) }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    private func scheduleReopenNotice(id: String) {
        notify(title: String(localized: "Poki Was Updated"), body: String(localized: "Tap to open Poki again."), id: id, after: 20)
    }

    /// Once a day in the last two days: the build is ready (or can't be made) and nothing installed it.
    private func remindIfExpiring() {
        guard let days = daysLeft, days <= Self.warnWithDaysLeft else { return }
        let key = "signing.reminded"
        if let last = UserDefaults.standard.object(forKey: key) as? Date, Date().timeIntervalSince(last) < 20 * 3600 { return }
        UserDefaults.standard.set(Date(), forKey: key)
        let when = expiry.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? ""
        notify(title: String(localized: "Poki Expires Soon"),
               body: next != nil ? String(localized: "A refreshed Poki is ready. Open Setup and tap Install before \(when).") : String(localized: "Open Setup to refresh Poki before \(when)."))
    }

    /// `-pokiSigningDays 1`: a simulator has no profile, so a screenshot gives Poki one that ends then.
    nonisolated private static var screenshotExpiry: Date? {
        #if targetEnvironment(simulator)
        guard UserDefaults.standard.object(forKey: "pokiSigningDays") != nil else { return nil }
        return Date().addingTimeInterval(UserDefaults.standard.double(forKey: "pokiSigningDays") * 86_400)
        #else
        nil
        #endif
    }

    /// The ExpirationDate of Poki's own embedded.mobileprovision (a CMS envelope around a plist).
    nonisolated static func installedProfileExpiry() -> Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return nil }
        let plist = data.subdata(in: start.lowerBound..<end.upperBound)
        let dict = (try? PropertyListSerialization.propertyList(from: plist, format: nil)) as? [String: Any]
        return dict?["ExpirationDate"] as? Date
    }
}

struct SignerError: LocalizedError {
    let message: String
    let code: String
    var errorDescription: String? { message }
}

/// A JSON value of any shape, for answers that need no struct.
struct AnyDecodable: Decodable {
    let value: Any
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { value = b }
        else if let n = try? c.decode(Double.self) { value = n }
        else if let s = try? c.decode(String.self) { value = s }
        else if let a = try? c.decode([AnyDecodable].self) { value = a.map(\.value) }
        else if let d = try? c.decode([String: AnyDecodable].self) { value = d.mapValues(\.value) }
        else { value = NSNull() }
    }
}

/// poki_signer_* through the C ABI.
enum SignerBridge {
    fileprivate static let prefix = "signer."

    /// The Keychain as the signer's vault (Keychain items are after-first-unlock, this device only).
    static func installVault() {
        _ = poki_signer_set_vault({ _, name in
            guard let name, let data = try? Keychain.read(SignerBridge.prefix + String(cString: name)) else { return nil }
            return strdup(data.base64EncodedString())
        }, { _, name, value in
            guard let name, let value, let data = Data(base64Encoded: String(cString: value)) else { return -1 }
            do { try Keychain.write(data, account: SignerBridge.prefix + String(cString: name)); return 0 } catch { return -2 }
        }, { _, name in
            guard let name else { return -1 }
            Keychain.delete(SignerBridge.prefix + String(cString: name))
            return 0
        }, nil)
    }

    final class Box: @unchecked Sendable {
        let progress: (@Sendable ([String: Any]) -> Void)?
        var continuation: CheckedContinuation<Data, Error>?
        init(progress: (@Sendable ([String: Any]) -> Void)?, continuation: CheckedContinuation<Data, Error>) {
            self.progress = progress
            self.continuation = continuation
        }
    }

    /// Runs one request; the answer's `value` as JSON (wrapped as {"v": value}).
    @discardableResult
    static func call(_ request: [String: Any], progress: (@Sendable ([String: Any]) -> Void)? = nil) async throws -> Data {
        let json = try JSONSerialization.data(withJSONObject: request)
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data, Error>) in
            let box = Unmanaged.passRetained(Box(progress: progress, continuation: c))
            let rc = String(decoding: json, as: UTF8.self).withCString { text in
                poki_signer_call(text, { context, event in
                    guard let context, let event else { return }
                    let unmanaged = Unmanaged<Box>.fromOpaque(context)
                    let box = unmanaged.takeUnretainedValue()
                    guard let object = (try? JSONSerialization.jsonObject(with: Data(String(cString: event).utf8))) as? [String: Any] else { return }
                    if object["event"] as? String == "result" {
                        if object["ok"] as? Bool == true {
                            let wrapped = (try? JSONSerialization.data(withJSONObject: ["v": object["value"] ?? NSNull()])) ?? Data("{\"v\":null}".utf8)
                            box.continuation?.resume(returning: wrapped)
                        } else {
                            box.continuation?.resume(throwing: SignerError(message: object["error"] as? String ?? "The signer failed.", code: object["code"] as? String ?? ""))
                        }
                        box.continuation = nil
                        unmanaged.release()
                    } else if let p = object["progress"] as? [String: Any] {
                        box.progress?(p)
                    }
                }, box.toOpaque())
            }
            if rc != 0 {
                box.takeUnretainedValue().continuation = nil
                box.release()
                c.resume(throwing: SignerError(message: "The signer did not take the request.", code: "config"))
            }
        }
    }

    private struct Wrapped<T: Decodable>: Decodable { let v: T }

    static func decode<T: Decodable>(_ type: T.Type, _ request: [String: Any], progress: (@Sendable ([String: Any]) -> Void)? = nil) async throws -> T {
        let data = try await call(request, progress: progress)
        return try JSONDecoder().decode(Wrapped<T>.self, from: data).v
    }
}
