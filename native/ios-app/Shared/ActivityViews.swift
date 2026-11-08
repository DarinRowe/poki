// The Live Activity's views. The structure (one card per surface drawn from one presentation, the
// expanded island's content under the camera, the approval buttons, the compact status) is ported
// from AgentLiveActivityWidget.swift in Clarklevis1995/dsh-mobile (commit ebe19764,
// AgentLiveActivityWidget/AgentLiveActivityWidget.swift), MIT License, Copyright (c) 2026 Chaofan Li.
// The approval countdown, counted by the system with `Text(timerInterval:countsDown:)`, follows
// ios/AgentActivity/AgentActivityWidget.swift in onehumanbeing/esp32-iphone-agent (commit cc966294),
// MIT License, Copyright (c) 2026 Henry Yuan. Interpolated text, the phase spring and margins kept
// concentric with the island's corners are from leepokai/Codync (commit 848070d,
// apps/ios/Widgets/CodyncWidgets.swift), Copyright 2026 Po Kai Lee, Apache License 2.0. Poki adds the
// step line, the pairing code, the setup steps, the thumbnail and the bear avatar from ESP-139's
// board 02, with ESP-162's shorter words. See THIRD_PARTY_NOTICES.md.
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Sizes (HIG, iPhone): the Lock Screen presentation and the expanded island are 84 to 160 points tall
/// and 371 or 408 wide. Every view here draws one `ActivityFace`, so the four presentations say the
/// same thing in the same order: the state glyph, the status word, then the content line.
enum ActivityMetrics {
    /// The Lock Screen's margins: the system's standard 14 points, 16 at the sides so the glyph and
    /// the buttons stay clear of the rounded corners.
    static let lockInsets = EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
    /// The card's corner as iOS draws it (the in-app preview's frame).
    static let lockCorner: CGFloat = 24
    /// The expanded island's margins inside its 44 point corners: content never runs to the edge.
    static let islandInsets = EdgeInsets(top: 18, leading: 24, bottom: 22, trailing: 24)
    static let islandCorner: CGFloat = 44
    /// The row beside the camera sits a little further from the island's rounded sides.
    static let islandRowInset: CGFloat = 4
    static let glyph: CGFloat = 15
    static let stop: CGFloat = 32
}

// MARK: Lock Screen

/// The Lock Screen (and banner) presentation: the status row, the content line in the large size,
/// and at most one action under it.
struct LockScreenCard: View {
    var face: ActivityFace
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StatusRow(face: face, surface: .lockScreen)
            ContentRow(face: face)
            ActionRow(face: face, surface: .lockScreen)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ActivityMetrics.lockInsets)
        // No animation in Always On (HIG).
        .animation(dimmed ? nil : ActivityMotion.phase, value: face)
        .accessibilityElement(children: .contain)
    }
}

/// The glyph, the status word and the meta value.
private struct StatusRow: View {
    var face: ActivityFace
    var surface: ActivitySurface
    private let theme = ActivityTheme.current
    var body: some View {
        HStack(spacing: 6) {
            StateGlyph(face: face)
            Text(face.status)
                .font(theme.status)
                .foregroundStyle(theme.palette(surface).color(face.tone))
                .lineLimit(1)
                .contentTransition(.interpolate)
            Spacer(minLength: 8)
            MetaView(meta: face.meta, surface: surface)
            if let caller = face.caller { CallerBadge(name: caller, size: 20) }
        }
    }
}

/// The content line and, while working, Stop beside it.
private struct ContentRow: View {
    var face: ActivityFace
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ContentLine(face: face)
                .frame(maxWidth: .infinity, alignment: .leading)
            if face.bottom == .stop { StopButton().transition(.opacity) }
        }
    }
}

/// The one thing in the large size, up to two lines.
private struct ContentLine: View {
    var face: ActivityFace
    private let theme = ActivityTheme.current
    var body: some View {
        Text(face.content)
            .font(face.contentIsCode ? theme.content.monospacedDigit().weight(.bold) : theme.content)
            .foregroundStyle(face.stale ? AnyShapeStyle(HierarchicalShapeStyle.secondary) : AnyShapeStyle(HierarchicalShapeStyle.primary))
            .lineLimit(face.contentIsCode ? 1 : 2)
            .minimumScaleFactor(0.85)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(face.contentIsCode ? .numericText() : .interpolate)
    }
}

/// Under the content line: the approval's decision, Done for a handoff, or setup's progress bar.
private struct ActionRow: View {
    var face: ActivityFace
    var surface: ActivitySurface
    private let theme = ActivityTheme.current
    var body: some View {
        switch face.bottom {
        case .none, .stop:
            EmptyView()
        case .approval(let id):
            ApprovalButtons(approvalID: id, surface: surface)
                .padding(.top, 4)
                .transition(.activityRow)
        case .handoff(let id):
            HandoffDoneButton(handoffID: id, surface: surface)
                .padding(.top, 4)
                .transition(.activityRow)
        case .progress(let fraction):
            ProgressView(value: min(1, max(0, fraction)))
                .tint(theme.palette(surface).accent)
                .padding(.top, 4)
                .transition(.activityRow)
        }
    }
}

// MARK: Dynamic Island, expanded

/// Beside the camera, left: the glyph and the short status word.
struct IslandLeading: View {
    var face: ActivityFace
    private let theme = ActivityTheme.current
    var body: some View {
        HStack(spacing: 6) {
            StateGlyph(face: face)
            Text(face.shortStatus)
                .font(theme.status)
                .foregroundStyle(theme.island.color(face.tone))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.interpolate)
        }
        .padding(.leading, ActivityMetrics.islandRowInset)
        .frame(maxHeight: .infinity, alignment: .center)
        .environment(\.colorScheme, .dark)
    }
}

/// Beside the camera, right: the meta value.
struct IslandTrailing: View {
    var face: ActivityFace
    var body: some View {
        HStack(spacing: 6) {
            MetaView(meta: face.meta, surface: .island)
            if let caller = face.caller { CallerBadge(name: caller, size: 20) }
        }
            .padding(.trailing, ActivityMetrics.islandRowInset)
            .frame(maxHeight: .infinity, alignment: .center)
            .environment(\.colorScheme, .dark)
    }
}

/// Under the camera: the content line (with Stop) and the action, as on the Lock Screen.
struct IslandBottom: View {
    var face: ActivityFace
    @Environment(\.isLuminanceReduced) private var dimmed
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ContentRow(face: face)
            ActionRow(face: face, surface: .island)
        }
        .padding(.bottom, face.hasAction ? 0 : 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.colorScheme, .dark)
        .animation(dimmed ? nil : ActivityMotion.phase, value: face)
    }
}

// MARK: Dynamic Island, compact and minimal

/// The state glyph: the same mark as in the other presentations, so the compact island reads as the
/// same activity at a glance.
struct CompactLeading: View {
    var face: ActivityFace
    var body: some View {
        StateGlyph(face: face).padding(.leading, 2).environment(\.colorScheme, .dark)
    }
}

/// A short value rather than a sentence, so it never truncates.
struct CompactTrailing: View {
    var face: ActivityFace
    private let theme = ActivityTheme.current
    var body: some View {
        let palette = theme.island
        Group {
            switch face.compact {
            case .text(let text, let tone):
                Text(text).font(theme.compact).foregroundStyle(palette.color(tone))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
            case .code(let code):
                Text(code).font(theme.compactCode).foregroundStyle(palette.accent)
                    .lineLimit(1).minimumScaleFactor(0.7)
            case .countdown(let until):
                CountdownText(until: until, color: palette.approval, width: 44)
            case .elapsed(let since):
                ElapsedText(since: since, color: palette.approval, width: 44)
            }
        }
        .frame(maxWidth: 64, alignment: .trailing)
        .padding(.trailing, 2)
        .environment(\.colorScheme, .dark)
    }
}

/// Another activity shares the island: the state glyph alone, which changes with the state.
struct MinimalView: View {
    var face: ActivityFace
    var body: some View {
        StateGlyph(face: face).environment(\.colorScheme, .dark)
    }
}

// MARK: Pieces

/// The state's SF Symbol in its colour: no container, no app icon (HIG).
struct StateGlyph: View {
    var face: ActivityFace
    private let theme = ActivityTheme.current
    var body: some View {
        Image(systemName: face.symbol)
            .font(.system(size: ActivityMetrics.glyph, weight: .semibold))
            .foregroundStyle(theme.lock.color(face.tone))
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }
}

/// The top-right value: a count, the approval's countdown, a time of day, or the time waited.
private struct MetaView: View {
    var meta: ActivityFace.Meta
    var surface: ActivitySurface
    private let theme = ActivityTheme.current
    var body: some View {
        let palette = theme.palette(surface)
        switch meta {
        case .none:
            EmptyView()
        case .text(let text):
            Text(text).font(theme.meta).foregroundStyle(palette.quiet)
                .lineLimit(1).minimumScaleFactor(0.8)
                .contentTransition(.numericText())
        case .countdown(let until):
            CountdownText(until: until, color: palette.approval, width: 48)
        case .clock(let date):
            Text(date, style: .time).font(theme.meta).foregroundStyle(palette.quiet)
                .lineLimit(1)
        case .elapsed(let since):
            ElapsedText(since: since, color: palette.approval, width: 48)
        }
    }
}

/// Deny and Allow: one decision, in the system's button styles. Allow asks for Face ID first (see
/// ApproveActionIntent), so it carries the Face ID glyph, in the button's own text colour.
struct ApprovalButtons: View {
    var approvalID: String
    var surface: ActivitySurface
    private let theme = ActivityTheme.current

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: DenyActionIntent(approvalID: approvalID)) {
                Text(String(activity: "Deny"))
                    .font(theme.button)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
            .foregroundStyle(.primary)
            Button(intent: ApproveActionIntent(approvalID: approvalID)) {
                Label(String(activity: "Allow"), systemImage: "faceid")
                    .font(theme.button)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.palette(surface).approval)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.regular)
    }
}

/// The one button on the "Your turn" card: the person finished what the agent could not do, and the
/// agent carries on (HandoffDoneIntent).
struct HandoffDoneButton: View {
    var handoffID: String
    var surface: ActivitySurface
    private let theme = ActivityTheme.current

    var body: some View {
        Button(intent: HandoffDoneIntent(handoffID: handoffID)) {
            Label(String(activity: "Done, carry on"), systemImage: "checkmark")
                .font(theme.button)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.regular)
        .tint(theme.palette(surface).approval)
    }
}

/// Stop runner: stops the runner, and with it iOS's automation banner, until the agent's next request.
/// The stop symbol, no word; VoiceOver reads "Stop".
struct StopButton: View {
    var body: some View {
        Button(intent: StopRunnerIntent()) {
            Image(systemName: "stop.fill")
                .font(.system(size: 13, weight: .bold))
                .frame(width: ActivityMetrics.stop - 12, height: ActivityMetrics.stop - 12)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .tint(.secondary)
        .foregroundStyle(.primary)
        .accessibilityLabel(String(activity: "Stop"))
    }
}

/// An approval's time left, counted down by the system between updates.
private struct CountdownText: View {
    var until: Date
    var color: Color
    var width: CGFloat
    var body: some View {
        // No fixedSize on timer text: it blanks the whole card on iOS 26.
        Text(timerInterval: Countdown.range(until), countsDown: true)
            .font(ActivityTheme.current.countdown).foregroundStyle(color)
            .multilineTextAlignment(.trailing)
            .frame(width: width, alignment: .trailing)
    }
}

/// How long the agent has waited for the person, counted up by the system.
private struct ElapsedText: View {
    var since: Date
    var color: Color
    var width: CGFloat
    var body: some View {
        Text(timerInterval: since...since.addingTimeInterval(12 * 3600), countsDown: false)
            .font(ActivityTheme.current.countdown).foregroundStyle(color)
            .multilineTextAlignment(.trailing)
            .frame(width: width, alignment: .trailing)
    }
}

enum Countdown {
    /// Counting down to `until`. The start is fixed just under an hour before it (not "now", which the
    /// system may take at another moment than it draws), so the remaining time is always `until - now`.
    static func range(_ until: Date) -> ClosedRange<Date> { until.addingTimeInterval(-3599)...until }
}

/// The bear, round, like the website's avatar (the app's own screens; the Live Activity uses
/// `StateGlyph`).
struct BearMark: View {
    var size: CGFloat
    var body: some View {
        Image("Bear").resizable().scaledToFill()
            .frame(width: size, height: size)
            .clipShape(.circle)
            .accessibilityHidden(true)
    }
}

/// The latest screenshot, read from the App Group container (the app's own previews).
struct Thumbnail: View {
    /// The app's own previews draw this when there is no file.
    @MainActor static var previewImage: UIImage?
    var size: CGSize
    var corner: CGFloat
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        Group {
            if let image = (SharedContainer.thumbnailURL.flatMap { UIImage(contentsOfFile: $0.path) }) ?? Self.previewImage {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color(.tertiarySystemFill)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
    }
}
