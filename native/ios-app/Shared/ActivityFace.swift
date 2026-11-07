import Foundation

typealias PokiState = PokiActivityAttributes.ContentState

/// What the Live Activity shows for a state, worked out once per phase. The Lock Screen, the expanded
/// island, the compact island and the minimal circle all draw this, so a phase's words and colours
/// live in one table (`PokiState.face`) instead of a switch in every view. The layout and colours
/// follow ESP-139's final board 02; the words are ESP-162's shorter ones: a status word and one
/// content line, and below them only the step line (with Stop), the setup steps or, for an approval,
/// Deny and Allow. See ActivityWords for the limits and the languages.
struct ActivityFace: Hashable {
    enum Meta: Hashable {
        case none
        /// A short count ("Step 7", "2/6").
        case text(String)
        /// The time left on an approval, counted down by the system.
        case countdown(Date)
        /// A time of day ("9:41 AM").
        case clock(Date)
        /// How long the agent has waited for the person, counted up by the system.
        case elapsed(Date)
    }
    enum Compact: Hashable {
        /// A short count ("Step 7", "2/6").
        case text(String, ActivityTone)
        /// The pairing code, tabular digits.
        case code(String)
        case countdown(Date)
        case symbol(String, ActivityTone)
    }
    enum Bottom: Hashable {
        case none
        /// One dot per step on a line, the missed ones larger and red, the current step hollow; the
        /// line turns green when the run is finished. Stop (an icon, no word) at its end while working.
        case progress(outcomes: [Bool], current: Bool, finished: Bool, stop: Bool)
        case approval(id: String)
        /// "Done, carry on" for a screen the agent handed to the person.
        case handoff(id: String)
        /// The setup steps: done, the current one, the rest.
        case segments(number: Int, count: Int)
    }
    enum Minimal: Hashable {
        case avatar
        /// The avatar in a ring that fills with the run's steps.
        case ring(Double)
        case approval
        case problem
    }

    /// The status word ("Approval"), coloured by `tone`.
    var status: String
    /// The same, short enough for the expanded island's leading region ("Stopped").
    var shortStatus: String
    var tone: ActivityTone
    /// The value at the status word's right, on the Lock Screen and beside the camera.
    var meta: Meta
    /// The content line, the one thing in the large size.
    var content: String
    /// The content is the pairing code.
    var contentIsCode = false
    var bottom: Bottom
    /// The latest screenshot beside the Lock Screen card's words (while working, when done, and for
    /// an approval).
    var thumbnail = false
    var compact: Compact
    var minimal: Minimal = .avatar
    /// Outline the island in the website's blue (an approval waiting).
    var outlined = false
}

extension PokiActivityAttributes.Event {
    var tone: ActivityTone {
        switch kind {
        case .started, .app, .code, .resumed: .accent
        case .handoff: .approval
        case .finished, .approved, .paired: .done
        case .denied, .expired: .quiet
        case .problem: .problem
        }
    }
}

extension PokiState {
    var hasThumbnail: Bool { thumbnailVersion > 0 }

    /// "12 steps in 1:24".
    var runLine: String {
        let steps = stepCount == 1 ? String(activity: "1 step") : String(activity: "\(stepCount) steps")
        guard let since, let endedAt else { return steps }
        let time = Duration.seconds(max(0, endedAt.timeIntervalSince(since))).formatted(.time(pattern: .minuteSecond))
        return String(activity: "\(steps) in \(time)")
    }

    /// The finished run for the alert: "12 steps in 1:24, 1 missed".
    var runSummary: String {
        failedCount > 0 ? String(activity: "\(runLine), \(failedCount) missed") : runLine
    }

    var face: ActivityFace {
        var face = baseFace
        // A fresh event ("Started", "Allowed") takes the status word's place for a few seconds, in
        // its own colour. An app switch keeps the app's name as the word and only lights it up.
        if let event, !phase.holdsApproval {
            let word = event.kind == .app ? (app ?? event.text) : ActivityWords.local(event.text)
            face.status = word
            face.shortStatus = word
            face.tone = event.tone
        }
        return face
    }

    private var baseFace: ActivityFace {
        let step = String(activity: "Step \(stepCount + 1)")
        switch phase {
        case .working:
            let name = app ?? String(activity: "Working")
            return ActivityFace(
                status: name, shortStatus: name, tone: .quiet, meta: .text(step),
                content: ActivityWords.step(headline),
                bottom: .progress(outcomes: outcomes, current: true, finished: false, stop: true),
                thumbnail: hasThumbnail,
                compact: .text(step, .plain),
                minimal: .ring(Double(outcomes.count) / Double(Self.outcomeLimit)))
        case .approval, .deciding:
            guard let approval else { return quietFace }
            let question = ActivityWords.brief(approval.question)
            if phase == .deciding {
                let allowed = decision == true
                let word = allowed ? String(activity: "Allowed") : String(activity: "Denied")
                return ActivityFace(
                    status: word, shortStatus: word, tone: allowed ? .approval : .quiet, meta: .none,
                    content: question, bottom: .none,
                    compact: .symbol(allowed ? "checkmark" : "xmark", allowed ? .approval : .quiet),
                    minimal: .approval)
            }
            let word = String(activity: "Approval")
            return ActivityFace(
                status: word, shortStatus: word, tone: .approval, meta: .countdown(approval.expires),
                content: question, bottom: .approval(id: approval.id),
                thumbnail: hasThumbnail,
                compact: .countdown(approval.expires),
                minimal: .approval,
                outlined: true)
        case .done:
            let word = String(activity: "Done")
            return ActivityFace(
                status: word, shortStatus: word, tone: .done, meta: endedAt.map { .clock($0) } ?? .none,
                content: runLine,
                bottom: .progress(outcomes: outcomes, current: false, finished: true, stop: false),
                thumbnail: hasThumbnail,
                compact: .symbol("checkmark", .done))
        case .problem:
            return ActivityFace(
                status: ActivityWords.local(label ?? "Problem"),
                shortStatus: label == "Pairing Failed" ? String(activity: "Failed") : String(activity: "Stopped"),
                tone: .problem, meta: .none,
                content: ActivityWords.brief(ActivityWords.local(headline)), bottom: .none,
                compact: .symbol("exclamationmark", .problem),
                minimal: .problem)
        case .pairing:
            if let pin {
                return ActivityFace(
                    status: String(activity: "Pairing Code"), shortStatus: String(activity: "Pairing"), tone: .accent, meta: .none,
                    content: pin.count == 6 ? "\(pin.prefix(3)) \(pin.suffix(3))" : pin, contentIsCode: true,
                    bottom: .none,
                    compact: .code(pin))
            }
            let word = String(activity: "Pairing")
            return ActivityFace(
                status: word, shortStatus: word, tone: .accent, meta: .none,
                content: String(activity: "Pair in Settings"), bottom: .none,
                compact: .symbol("link", .accent))
        case .setup:
            guard let guide else { return quietFace }
            let word = String(activity: "Setup")
            let count = "\(guide.number)/\(guide.count)"
            return ActivityFace(
                status: word, shortStatus: word, tone: .accent, meta: .text(count),
                content: ActivityWords.brief(ActivityWords.local(guide.title)),
                bottom: .segments(number: guide.number, count: guide.count),
                compact: .text(count, .plain))
        case .handoff:
            guard let handoff else { return quietFace }
            let word = String(activity: "Your turn")
            return ActivityFace(
                status: word, shortStatus: word, tone: .approval, meta: .elapsed(handoff.since),
                content: ActivityWords.brief(handoff.line),
                bottom: .handoff(id: handoff.id),
                compact: .symbol(handoff.symbol, .approval),
                minimal: .approval,
                outlined: true)
        case .idle:
            return quietFace
        }
    }

    /// Ready (the runner is up) and Idle (it sleeps until an agent asks).
    private var quietFace: ActivityFace {
        let word = runnerPaused ? String(activity: "Idle") : String(activity: "Ready")
        return ActivityFace(
            status: word, shortStatus: word, tone: runnerPaused ? .quiet : .done, meta: .none,
            content: ActivityWords.brief(ActivityWords.local(headline)), bottom: .none,
            compact: .symbol(runnerPaused ? "moon.zzz.fill" : "checkmark", runnerPaused ? .quiet : .done))
    }
}

extension PokiActivityAttributes.Handoff {
    /// What the person has to do, in the agent's place.
    var title: String {
        switch kind {
        case .runnerPasscode: String(activity: "Enter your passcode to start the runner")
        case .passcode: String(activity: "Enter your passcode")
        case .password: String(activity: "Fill in your password")
        case .verification: String(activity: "Pass the verification yourself")
        case .payment: String(activity: "Finish the payment yourself")
        case .other: String(activity: "Do this step yourself")
        }
    }
    /// The content line: a fixed short line per kind, so it fits the Live Activity's four words (eight
    /// characters in Chinese) whole. The agent's own note is the alert's second line (`detail`) and
    /// the app's issue row, where it has room.
    var line: String {
        kind == .runnerPasscode ? String(activity: "Passcode for the runner") : title
    }
    /// The agent's own note, or what happens next (the alert's second line).
    var detail: String {
        if let text, !text.isEmpty { return text }
        switch kind {
        case .runnerPasscode: return String(activity: "iOS asks for it once after a restart. The agent waits.")
        case .payment: return String(activity: "The agent does not pay for you. It waits, then carries on.")
        default: return String(activity: "The agent can't act on this screen. It waits for you.")
        }
    }
    var symbol: String {
        switch kind {
        case .runnerPasscode, .passcode: "lock.fill"
        case .password: "key.fill"
        case .verification: "checkmark.shield.fill"
        case .payment: "creditcard.fill"
        case .other: "person.fill"
        }
    }
}
