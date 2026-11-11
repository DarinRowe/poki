import Foundation

/// Which method carries out a task, decided from what this iPhone can do right now. Poki has two:
/// native services (the paired developer services: no banner, needs the tunnel at 10.7.0.1, which iOS
/// only opens on Wi-Fi) and the XCTest session (iOS's test service inside the phone: a banner, and no
/// network at all once the developer image is mounted). The choice is made only between tasks (when
/// Poki turns on, when an agent asks after a pause, when the connection changes while nothing runs,
/// and when the method in use has stopped answering), never in the middle of a step that works.
/// Native services come first; the XCTest session's banner is the owner's to agree to.
enum AutomationChooser {
    enum Method: String { case xctest, native }

    struct Conditions: Equatable {
        /// The iOS major version: native services cannot tap below 27 (issues 1 and 18).
        var iOS = 27
        /// The owner chose a method on the local connection page: nothing is decided for them.
        var pinned: Method?
        /// The method in use now.
        var current = Method.native
        /// 10.7.0.1 answers.
        var loopbackWorking = false
        /// The phone's only way out is cellular: iOS opens no new tunnel there.
        var cellularOnly = false
        /// Native services' tunnels are open (opened on Wi-Fi, they go on over cellular).
        var nativeTunnelsOpen = false
        /// The developer image's XCTest framework is in place, so a session can open with no network.
        var imageMounted = false
        /// The XCTest session of this launch is open.
        var xctestOpen = false
        /// The XCTest session of this launch was closed (one reopened in the same launch reads
        /// nothing), or the owner left iOS's passcode screen, or an open failed after its repairs.
        var xctestUnavailable = false
        /// Native services failed this many times in a row since they last worked.
        var nativeFailures = 0
        /// Wi-Fi is up.
        var onWiFi = true
        /// The owner agreed to the XCTest session (and iOS's banner) while native services cannot start.
        var bannerAllowed = false
    }

    /// What the owner is asked before the XCTest session is used in place of native services.
    enum Ask: String, Equatable {
        /// On Wi-Fi, and nothing answers at 10.7.0.1: turning the loopback on is all it takes.
        case loopbackOff
        /// No Wi-Fi: iOS opens no connection for native services until there is one.
        case noWiFi
        /// The connection answers, but native services keep failing.
        case nativeFailing
    }

    struct Choice: Equatable {
        var method: Method
        /// For the log, in plain words.
        var why: String
        /// Native services cannot start now and the XCTest session could: the owner decides whether
        /// to fix the connection or to go on with the session and its banner. Nil when there is
        /// nothing to ask.
        var ask: Ask?
    }

    /// How many native failures in a row bring the question up.
    static let nativeFailureLimit = 2

    /// Native services wherever the iPhone supports them. The XCTest session takes over only where
    /// it is the one method there is (before iOS 27), where the owner chose it, or where native
    /// services cannot start and the owner agreed to the banner.
    static func choose(_ c: Conditions) -> Choice {
        if let pinned = c.pinned { return Choice(method: pinned, why: "chosen by the owner") }
        if c.iOS < 27 { return Choice(method: .xctest, why: "native services cannot send touches before iOS 27") }
        let xctestPossible = !c.xctestUnavailable && (c.imageMounted || c.xctestOpen)
        let failing = c.nativeFailures >= nativeFailureLimit
        // Tunnels that are open keep working wherever the phone goes.
        if c.nativeTunnelsOpen, !failing {
            return Choice(method: .native, why: "native services are connected")
        }
        let canOpenTunnel = c.loopbackWorking && !c.cellularOnly
        if canOpenTunnel, !failing {
            return Choice(method: .native, why: c.current == .xctest ? "the connection is back, so native services take over (no banner)" : "the connection answers")
        }
        // Native services cannot start now.
        let ask: Ask = canOpenTunnel ? .nativeFailing : c.cellularOnly || !c.onWiFi ? .noWiFi : .loopbackOff
        guard xctestPossible else {
            return Choice(method: .native, why: c.xctestUnavailable ? "native services cannot start, and the XCTest session cannot be used again in this launch"
                                                                  : "native services cannot start, and the developer image is not mounted")
        }
        if c.bannerAllowed {
            return Choice(method: .xctest, why: "the owner agreed to the XCTest session and its banner (\(ask.rawValue))")
        }
        return Choice(method: .native, why: "native services cannot start (\(ask.rawValue)); the owner is asked before the XCTest session is used", ask: ask)
    }
}

extension AutomationPath {
    /// The method the owner chose on the local connection page, if any: nothing is then chosen for them.
    /// Read once, as `current` is: a change takes effect when Poki starts again.
    static let pinned = savedMethod.flatMap(AutomationPath.init(rawValue:))
}
