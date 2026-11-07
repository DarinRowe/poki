import Foundation

typealias PokiState = PokiActivityAttributes.ContentState

/// What the Live Activity shows for a state, worked out once per phase. The Lock Screen, the expanded
/// island, the compact island and the minimal circle all draw this, so a phase's words and colours
/// live in one table (`PokiState.face`) instead of a switch in every view. The words follow ESP-139's
/// final board 02.
struct ActivityFace: Hashable {
    enum Meta: Hashable {
        case none
        case text(String)
        /// The time left on an approval, counted down by the system.
        case countdown(Date)
        /// A time of day ("9:41 AM").
        case clock(Date)
    }
    enum Compact: Hashable {
        /// Words and short counts ("Step 7", "2/6").
        case text(String, ActivityTone)
        /// The pairing code, tabular digits.
        case code(String)
        /// A single bold mark ("!").
        case mark(String, ActivityTone)
        case countdown(Date)
        case symbol(String, ActivityTone)
    }
    enum Bottom: Hashable {
        case none
        /// One dot per step on a line, the missed ones larger and red, the current step hollow; the
        /// line turns green when the run is finished. Stop beside it while working.
        case progress(outcomes: [Bool], current: Bool, finished: Bool, stop: Bool)
        case approval(id: String)
        /// The answer is on its way to PokiCore.
        case deciding(String)
        case openPoki
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
    enum Thumbnail: Hashable { case none, large, small }

    /// The status word on the Lock Screen ("Approval Required"), coloured by `tone`.
    var status: String
    /// The same, short enough for the expanded island's 100 points ("Approval").
    var shortStatus: String
    var tone: ActivityTone
    /// The Lock Screen's top-right value, and the expanded island's (shorter where it has to be).
    var meta: Meta
    var shortMeta: Meta
    var title: String
    /// The title is a pairing code in large digits.
    var titleIsCode = false
    var subtitle: String?
    var subtitleTone: ActivityTone = .quiet
    var bottom: Bottom
    var thumbnail: Thumbnail = .none
    var compact: Compact
    var minimal: Minimal = .avatar
    /// Outline the island in the website's blue (an approval waiting).
    var outlined = false
}

extension PokiActivityAttributes.Event {
    var tone: ActivityTone {
        switch kind {
        case .started, .app, .code: .accent
        case .finished, .approved, .paired: .done
        case .denied, .expired: .quiet
        case .problem: .problem
        }
    }
}

extension PokiState {
    var hasThumbnail: Bool { thumbnailVersion > 0 }

    /// "12 steps in 1:24, 1 missed".
    var runSummary: String {
        let steps = stepCount == 1 ? String(localized: "1 step") : String(localized: "\(stepCount) steps")
        var line = steps
        if let since, let endedAt {
            line += " " + String(localized: "in \(Duration.seconds(max(0, endedAt.timeIntervalSince(since))).formatted(.time(pattern: .minuteSecond)))")
        }
        return failedCount > 0 ? String(localized: "\(line), \(failedCount) missed") : line
    }

    var face: ActivityFace {
        var face = baseFace
        // A fresh event ("Started", "Allowed") takes the status word's place for a few seconds, in
        // its own colour. An app switch keeps the app's name as the word and only lights it up.
        if let event, !phase.holdsApproval {
            let word = event.kind == .app ? (app ?? event.text) : event.text
            face.status = word
            face.shortStatus = word
            face.tone = event.tone
        }
        return face
    }

    private var baseFace: ActivityFace {
        let step = String(localized: "Step \(stepCount + 1)")
        switch phase {
        case .working:
            let name = app ?? String(localized: "Working")
            return ActivityFace(
                status: name, shortStatus: name, tone: .quiet,
                meta: .text(step), shortMeta: .text(step),
                title: headline,
                bottom: .progress(outcomes: outcomes, current: true, finished: false, stop: true),
                thumbnail: hasThumbnail ? .large : .none,
                compact: .text(step, .plain),
                minimal: .ring(Double(outcomes.count) / Double(Self.outcomeLimit)))
        case .approval, .deciding:
            guard let approval else { return quietFace }
            if phase == .deciding {
                let allowed = decision == true
                let word = allowed ? String(localized: "Allowed") : String(localized: "Not Allowed")
                return ActivityFace(
                    status: word, shortStatus: word, tone: allowed ? .approval : .quiet,
                    meta: .none, shortMeta: .none,
                    title: approval.summary,
                    subtitle: approval.reasonLine, subtitleTone: .reason,
                    bottom: .deciding(allowed ? String(localized: "Continuing") : String(localized: "Telling the agent")),
                    thumbnail: hasThumbnail ? .small : .none,
                    compact: .symbol(allowed ? "checkmark" : "xmark", allowed ? .approval : .quiet),
                    minimal: .approval)
            }
            return ActivityFace(
                status: String(localized: "Approval Required"), shortStatus: String(localized: "Approval"), tone: .approval,
                meta: .countdown(approval.expires), shortMeta: .countdown(approval.expires),
                title: approval.summary,
                subtitle: approval.reasonLine, subtitleTone: .reason,
                bottom: .approval(id: approval.id),
                thumbnail: hasThumbnail ? .small : .none,
                compact: .countdown(approval.expires),
                minimal: .approval,
                outlined: true)
        case .done:
            let time: ActivityFace.Meta = endedAt.map { .clock($0) } ?? .none
            return ActivityFace(
                status: String(localized: "Done"), shortStatus: String(localized: "Done"), tone: .done,
                meta: time, shortMeta: time,
                title: headline, subtitle: runSummary,
                bottom: .progress(outcomes: outcomes, current: false, finished: true, stop: false),
                thumbnail: hasThumbnail ? .large : .none,
                compact: .symbol("checkmark", .done))
        case .problem:
            let meta: ActivityFace.Meta = stepCount > 0 ? .text(step) : .none
            return ActivityFace(
                status: label ?? String(localized: "Problem"), shortStatus: String(localized: "Stopped"), tone: .problem,
                meta: meta, shortMeta: meta,
                title: headline, subtitle: hint ?? String(localized: "Open Poki to fix it."),
                bottom: .openPoki,
                compact: .mark("!", .problem),
                minimal: .problem)
        case .pairing:
            if let pin {
                return ActivityFace(
                    status: String(localized: "Pairing Code"), shortStatus: String(localized: "Pairing"), tone: .accent,
                    meta: .text(String(localized: "Settings › Developer Mode")), shortMeta: .text(String(localized: "Settings")),
                    title: pin.count == 6 ? "\(pin.prefix(3)) \(pin.suffix(3))" : pin, titleIsCode: true,
                    subtitle: String(localized: "Tap Pair with Poki, then enter this code."),
                    bottom: .none,
                    compact: .code(pin))
            }
            return ActivityFace(
                status: String(localized: "Pairing"), shortStatus: String(localized: "Pairing"), tone: .accent,
                meta: .text(String(localized: "Settings › Developer Mode")), shortMeta: .text(String(localized: "Settings")),
                title: String(localized: "Pair in Settings"),
                subtitle: String(localized: "Open Pair with Poki there. The code shows up here."),
                bottom: .none,
                compact: .symbol("link", .accent))
        case .setup:
            guard let guide else { return quietFace }
            return ActivityFace(
                status: String(localized: "Setup"), shortStatus: String(localized: "Setup"), tone: .accent,
                meta: .text(String(localized: "Step \(guide.number) of \(guide.count)")),
                shortMeta: .text(String(localized: "\(guide.number) of \(guide.count)")),
                title: guide.title, subtitle: guide.hint,
                bottom: .segments(number: guide.number, count: guide.count),
                compact: .text("\(guide.number)/\(guide.count)", .plain))
        case .idle:
            return quietFace
        }
    }

    /// Ready (the runner is up) and Idle (it sleeps until an agent asks).
    private var quietFace: ActivityFace {
        let word = runnerPaused ? String(localized: "Idle") : String(localized: "Ready")
        return ActivityFace(
            status: word, shortStatus: word, tone: runnerPaused ? .quiet : .done,
            meta: .none, shortMeta: .none,
            title: headline,
            subtitle: hint ?? (runnerPaused ? String(localized: "The runner wakes when an agent asks.") : String(localized: "Runner on. Waiting for the agent.")),
            bottom: .none,
            compact: .symbol(runnerPaused ? "moon.zzz.fill" : "checkmark", runnerPaused ? .quiet : .done))
    }
}
