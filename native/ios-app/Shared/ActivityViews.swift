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
// board 02. See THIRD_PARTY_NOTICES.md.
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Sizes (HIG, iPhone): the Lock Screen card and the expanded island are 371 points wide and at most
/// 160 tall; anything taller is cut. Every view here draws `PokiState.face`, so the four
/// presentations always say the same thing. The sizes are ESP-139's final board 02.
enum ActivityMetrics {
    /// The Lock Screen card's padding: 14 top and bottom, 20 leading, 14 trailing.
    static let lockInsets = EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 14)
    /// The card's corner as iOS draws it, for the concentric corners inside it.
    static let lockCorner: CGFloat = 24
    /// Inside the card's padding: 140 points tall, 156 while an approval waits. Fixed, so the card
    /// does not grow or shrink as lines and screenshots come and go within a phase.
    static let lockContent: CGFloat = 112
    static let lockApprovalContent: CGFloat = 128
    /// The expanded island's margins inside its 44 point corners.
    static let islandInsets = EdgeInsets(top: 11, leading: 14, bottom: 16, trailing: 14)
    static let islandCorner: CGFloat = 44
    static let islandGap: CGFloat = 6
    /// iOS clips the expanded island's content to the island inset by about 13 points, with corners
    /// about 36 points round (measured on the iPhone 17 Pro simulator). At the board's margins the
    /// corners cut the bear, the meta's last letters and the ends of the last row, so those move in.
    /// The row beside the camera: extra room on the outer side.
    static let islandRowInset: CGFloat = 14
    /// The last row: extra room below it, more for a flat row than for a capsule, and the setup
    /// steps narrower as well.
    static func islandBottomExtra(_ bottom: ActivityFace.Bottom) -> CGFloat {
        switch bottom {
        case .none: 18
        default: 8
        }
    }
    static let islandSegmentsInset: CGFloat = 10

    static let avatar: CGFloat = 20
    static let compactAvatar: CGFloat = 22
    static let thumbnail = CGSize(width: 52, height: 112)
    static let smallThumbnail = CGSize(width: 34, height: 72)
    /// Concentric with the card: its corner less the inset.
    static let thumbnailCorner = lockCorner - lockInsets.top
    static let smallThumbnailCorner: CGFloat = 7

    static func buttonHeight(_ surface: ActivitySurface) -> CGFloat { surface == .lockScreen ? 44 : 38 }
    static let denyWidth: CGFloat = 96
    static func stopWidth(_ surface: ActivitySurface) -> CGFloat { surface == .lockScreen ? 80 : 92 }
    static let stopHeight: CGFloat = 36
    static let openWidth: CGFloat = 120
    static func openHeight(_ surface: ActivitySurface) -> CGFloat { surface == .lockScreen ? 40 : 36 }

    static let dot: CGFloat = 8
    static let missedDot: CGFloat = 10
    static let lastDot: CGFloat = 12
    static let currentDot: CGFloat = 13
    static let dotSlot: CGFloat = 22
    static let line: CGFloat = 3
}

// MARK: Lock Screen

/// The Lock Screen (and banner) card, with its padding and the glass edge. The widget adds the blue
/// background tint.
struct LockScreenCard: View {
    var state: PokiState
    private let theme = ActivityTheme.current

    var body: some View {
        let face = state.face
        content(face)
            .padding(ActivityMetrics.lockInsets)
            .foregroundStyle(theme.lock.text)
            .overlay { GlassEdge() }
            .animation(ActivityMotion.phase, value: face)
    }

    @ViewBuilder
    private func content(_ face: ActivityFace) -> some View {
        switch face.bottom {
        case .approval, .deciding:
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        StatusRow(face: face)
                        Title(face: face, surface: .lockScreen)
                        Subtitle(face: face, surface: .lockScreen)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if face.thumbnail != .none {
                        Thumbnail(size: ActivityMetrics.smallThumbnail, corner: ActivityMetrics.smallThumbnailCorner)
                    }
                }
                Spacer(minLength: 8)
                BottomControl(face: face, surface: .lockScreen)
            }
            .frame(height: ActivityMetrics.lockApprovalContent)
        case .progress:
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    StatusRow(face: face)
                    Spacer(minLength: 4)
                    VStack(alignment: .leading, spacing: 0) {
                        Title(face: face, surface: .lockScreen)
                        Subtitle(face: face, surface: .lockScreen)
                    }
                    Spacer(minLength: 4)
                    BottomControl(face: face, surface: .lockScreen)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if face.thumbnail != .none {
                    Thumbnail(size: ActivityMetrics.thumbnail, corner: ActivityMetrics.thumbnailCorner)
                }
            }
            .frame(height: ActivityMetrics.lockContent)
        default:
            VStack(alignment: .leading, spacing: 0) {
                StatusRow(face: face)
                Spacer(minLength: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Title(face: face, surface: .lockScreen)
                    Subtitle(face: face, surface: .lockScreen)
                }
                if face.bottom != .none {
                    Spacer(minLength: 4)
                    BottomControl(face: face, surface: .lockScreen)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: ActivityMetrics.lockContent)
            .padding(.trailing, 6)
        }
    }
}

/// The 1 point glass line around the blue card, brighter along the top, as on the website's cards.
private struct GlassEdge: View {
    private let theme = ActivityTheme.current
    var body: some View {
        ContainerRelativeShape()
            .strokeBorder(
                LinearGradient(colors: [theme.glassHighlight, theme.glassEdge, theme.glassEdge], startPoint: .top, endPoint: .bottom),
                lineWidth: 1)
            .allowsHitTesting(false)
    }
}

/// The Lock Screen's top row: the bear, the status word and the meta value.
private struct StatusRow: View {
    var face: ActivityFace
    private let theme = ActivityTheme.current
    var body: some View {
        HStack(spacing: 6) {
            BearMark(size: ActivityMetrics.avatar)
            Text(face.status)
                .font(theme.status)
                .foregroundStyle(theme.lock.color(face.tone))
                .lineLimit(1)
                .contentTransition(.interpolate)
            Spacer(minLength: 8)
            MetaView(meta: face.meta, surface: .lockScreen)
        }
        .frame(height: ActivityMetrics.avatar)
    }
}

private struct Title: View {
    var face: ActivityFace
    var surface: ActivitySurface
    private let theme = ActivityTheme.current
    var body: some View {
        if face.titleIsCode {
            Text(face.title)
                .font(theme.code)
                .tracking(theme.codeTracking)
                .foregroundStyle(theme.palette(surface).text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 52)
                .contentTransition(.numericText())
        } else {
            Text(face.title)
                .font(theme.title)
                .tracking(theme.titleTracking)
                .foregroundStyle(theme.palette(surface).text)
                .lineLimit(1)
                .frame(height: 25)
                .contentTransition(.interpolate)
        }
    }
}

private struct Subtitle: View {
    var face: ActivityFace
    var surface: ActivitySurface
    private let theme = ActivityTheme.current
    var body: some View {
        if let subtitle = face.subtitle {
            // Setup hints may take two lines; everything else keeps to one.
            let twoLines = face.bottom.isSegments
            Text(subtitle)
                .font(theme.subtitle)
                .foregroundStyle(theme.palette(surface).color(face.subtitleTone))
                .lineLimit(twoLines ? 2 : 1)
                .lineSpacing(twoLines ? 2 : 0)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.interpolate)
        }
    }
}

extension ActivityFace.Bottom {
    var isSegments: Bool { if case .segments = self { true } else { false } }
}

// MARK: Dynamic Island, expanded

/// Beside the camera, left: the bear and the short status word.
struct IslandLeading: View {
    var state: PokiState
    private let theme = ActivityTheme.current
    var body: some View {
        let face = state.face
        HStack(spacing: 6) {
            BearMark(size: ActivityMetrics.avatar)
            Text(face.shortStatus)
                .font(theme.status)
                .foregroundStyle(theme.island.color(face.tone))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.interpolate)
        }
        .padding(.leading, ActivityMetrics.islandRowInset)
        .frame(maxHeight: .infinity, alignment: .center)
        .animation(ActivityMotion.phase, value: face)
    }
}

/// Beside the camera, right: the short meta value.
struct IslandTrailing: View {
    var state: PokiState
    var body: some View {
        let face = state.face
        MetaView(meta: face.shortMeta, surface: .island)
            .padding(.trailing, ActivityMetrics.islandRowInset)
            .frame(maxHeight: .infinity, alignment: .center)
            .animation(ActivityMotion.phase, value: face)
    }
}

/// Under the camera: the title, the subtitle and the phase's control.
struct IslandBottom: View {
    var state: PokiState
    var body: some View {
        let face = state.face
        VStack(alignment: .leading, spacing: ActivityMetrics.islandGap) {
            VStack(alignment: .leading, spacing: face.bottom.isSegments ? 2 : 0) {
                Title(face: face, surface: .island)
                Subtitle(face: face, surface: .island)
            }
            BottomControl(face: face, surface: .island)
        }
        .padding(.bottom, ActivityMetrics.islandBottomExtra(face.bottom))
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(ActivityTheme.current.island.text)
        .animation(ActivityMotion.phase, value: face)
    }
}

// MARK: Dynamic Island, compact and minimal

struct CompactLeading: View {
    var state: PokiState
    var body: some View { BearMark(size: ActivityMetrics.compactAvatar) }
}

/// A short value rather than a sentence, so it never truncates.
struct CompactTrailing: View {
    var state: PokiState
    private let theme = ActivityTheme.current
    var body: some View {
        let palette = theme.island
        Group {
            switch state.face.compact {
            case .text(let text, let tone):
                Text(text).font(theme.compact).foregroundStyle(palette.color(tone))
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .contentTransition(.numericText())
            case .code(let code):
                Text(code).font(theme.compactCode).foregroundStyle(palette.accent)
                    .lineLimit(1).minimumScaleFactor(0.8)
            case .mark(let mark, let tone):
                Text(mark).font(theme.compactMark).foregroundStyle(palette.color(tone))
            case .countdown(let until):
                // No fixedSize on timer text: it blanks the whole card on iOS 26.
                Text(timerInterval: Countdown.range(until), countsDown: true)
                    .font(theme.countdown).foregroundStyle(palette.approval)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 36, alignment: .trailing)
            case .symbol(let name, let tone):
                Image(systemName: name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.color(tone))
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .padding(.trailing, 4)
    }
}

/// Another app's activity shares the island: the one thing that matters, around the bear.
struct MinimalView: View {
    var state: PokiState
    private let theme = ActivityTheme.current
    var body: some View {
        switch state.face.minimal {
        case .avatar:
            BearMark(size: ActivityMetrics.avatar)
        case .ring(let progress):
            ZStack {
                Circle().stroke(theme.island.track, lineWidth: 2)
                Circle().trim(from: 0, to: max(0.04, min(1, progress)))
                    .stroke(theme.island.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                BearMark(size: 16)
            }
            .frame(width: 24, height: 24)
        case .approval:
            ZStack {
                Circle().strokeBorder(theme.approvalOutline, lineWidth: 2)
                BearMark(size: 16)
            }
            .frame(width: 24, height: 24)
        case .problem:
            Text("!").font(theme.compactMark).foregroundStyle(theme.island.problem)
        }
    }
}

// MARK: Pieces

/// The top-right value: text, the approval's countdown or a time of day.
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
            Text(timerInterval: Countdown.range(until), countsDown: true)
                .font(theme.countdown).foregroundStyle(palette.approval)
                .multilineTextAlignment(.trailing)
                .frame(width: 40, alignment: .trailing)
        case .clock(let date):
            Text(date, style: .time).font(theme.meta).foregroundStyle(palette.quiet)
                .lineLimit(1)
        }
    }
}

/// What sits at the bottom of a card: the step line and Stop, the approval buttons, Open Poki, the
/// setup steps.
private struct BottomControl: View {
    var face: ActivityFace
    var surface: ActivitySurface
    private let theme = ActivityTheme.current

    var body: some View {
        let palette = theme.palette(surface)
        switch face.bottom {
        case .none:
            EmptyView()
        case .progress(let outcomes, let current, let finished, let stop):
            HStack(spacing: 8) {
                StepLine(outcomes: outcomes, current: current, finished: finished,
                         capacity: capacity(stop: stop), palette: palette)
                Spacer(minLength: 0)
                if stop { StopButton(surface: surface).transition(.opacity) }
            }
            // The island keeps Stop's height when the run ends, so it does not shrink at Done.
            .frame(height: stop || surface == .island ? ActivityMetrics.stopHeight : 16)
            .transition(.activityRow)
        case .approval(let id):
            ApprovalButtons(approvalID: id, surface: surface)
                .transition(.activityRow)
        case .deciding(let text):
            Text(text)
                .font(theme.button)
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: ActivityMetrics.buttonHeight(surface), maxHeight: ActivityMetrics.buttonHeight(surface))
                .background(palette.buttonFill, in: .capsule)
                .contentTransition(.interpolate)
        case .openPoki:
            HStack {
                Spacer(minLength: 0)
                Link(destination: URL(string: "poki://home")!) {
                    Text("Open Poki")
                        .font(theme.button)
                        .foregroundStyle(palette.primaryText)
                        .frame(width: ActivityMetrics.openWidth, height: ActivityMetrics.openHeight(surface))
                        .background(palette.primaryFill, in: .capsule)
                }
            }
            .transition(.activityRow)
        case .segments(let number, let count):
            HStack(spacing: 4) {
                ForEach(1...max(1, count), id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(index < number ? palette.segmentDone : index == number ? palette.text : palette.track)
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, surface == .island ? ActivityMetrics.islandSegmentsInset : 0)
            .transition(.activityRow)
        }
    }

    /// How many dots fit beside Stop (or without it) on this surface, the current step included.
    private func capacity(stop: Bool) -> Int {
        switch (surface, stop) {
        case (.lockScreen, true): 8
        case (.lockScreen, false): 12
        case (.island, true): 11
        case (.island, false): 15
        }
    }
}

/// One dot per step on a 3 point line: plain when the step went through, larger and red when it did
/// not, the current step hollow. A finished run turns the line green and ends on a larger dot. The
/// newest steps are kept when they do not all fit.
private struct StepLine: View {
    var outcomes: [Bool]
    var current: Bool
    var finished: Bool
    var capacity: Int
    var palette: ActivityPalette
    private let theme = ActivityTheme.current

    var body: some View {
        let shown = Array(outcomes.suffix(max(0, capacity - (current ? 1 : 0))).enumerated())
        let slots = shown.count + (current ? 1 : 0)
        let slot = ActivityMetrics.dotSlot
        let line = finished ? palette.finished : theme.stepLine
        ZStack(alignment: .leading) {
            if slots > 1 {
                Capsule().fill(line)
                    .frame(width: CGFloat(slots - 1) * slot, height: ActivityMetrics.line)
                    .padding(.leading, slot / 2)
            }
            HStack(spacing: 0) {
                ForEach(shown, id: \.offset) { index, ok in
                    let last = finished && index == shown.count - 1 && ok
                    let size = last ? ActivityMetrics.lastDot : ok ? ActivityMetrics.dot : ActivityMetrics.missedDot
                    Circle()
                        .fill(ok ? line : theme.stepMissed)
                        .frame(width: size, height: size)
                        .frame(width: slot)
                }
                if current {
                    ZStack {
                        Circle().fill(theme.stepLine)
                        Circle().fill(theme.stepHole).padding(ActivityMetrics.line)
                    }
                    .frame(width: ActivityMetrics.currentDot, height: ActivityMetrics.currentDot)
                    .frame(width: slot)
                    .transition(.opacity)
                }
            }
        }
        .frame(height: 16)
        // The first dot's edge, not its slot, lines up with the text above.
        .padding(.leading, -(slot - ActivityMetrics.dot) / 2)
        .animation(ActivityMotion.phase, value: outcomes)
    }
}

/// Don't Allow and Allow. Allow asks for Face ID first (see ApproveActionIntent), so it carries the
/// Face ID glyph.
struct ApprovalButtons: View {
    var approvalID: String
    var surface: ActivitySurface
    private let theme = ActivityTheme.current

    var body: some View {
        let palette = theme.palette(surface)
        let height = ActivityMetrics.buttonHeight(surface)
        HStack(spacing: 8) {
            Button(intent: DenyActionIntent(approvalID: approvalID)) {
                Text("Don’t Allow")
                    .font(theme.button)
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(width: ActivityMetrics.denyWidth, height: height)
                    .background(palette.buttonFill, in: .capsule)
            }
            .buttonStyle(.plain)
            Button(intent: ApproveActionIntent(approvalID: approvalID)) {
                HStack(spacing: 6) {
                    Image(systemName: "faceid").font(.system(size: 16, weight: .medium)).foregroundStyle(theme.primaryIcon)
                    Text("Allow").font(theme.button).foregroundStyle(palette.primaryText)
                }
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
                .background(palette.primaryFill, in: .capsule)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Stop runner: stops the runner, and with it iOS's automation banner, until the agent's next request.
struct StopButton: View {
    var surface: ActivitySurface
    private let theme = ActivityTheme.current
    var body: some View {
        let palette = theme.palette(surface)
        Button(intent: StopRunnerIntent()) {
            Text("Stop")
                .font(theme.button)
                .foregroundStyle(palette.text)
                .frame(width: ActivityMetrics.stopWidth(surface), height: ActivityMetrics.stopHeight)
                .background(palette.buttonFill, in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

enum Countdown {
    /// Counting down to `until`. The start is fixed just under an hour before it (not "now", which the
    /// system may take at another moment than it draws), so the remaining time is always `until - now`.
    static func range(_ until: Date) -> ClosedRange<Date> { until.addingTimeInterval(-3599)...until }
}

/// The bear, round, like the website's avatar.
struct BearMark: View {
    var size: CGFloat
    var body: some View {
        Image("Bear").resizable().scaledToFill()
            .frame(width: size, height: size)
            .clipShape(.circle)
            .accessibilityHidden(true)
    }
}

/// The latest screenshot, read from the App Group container and drawn like a small phone. The view is
/// drawn again with every update, so a new file shows in place, without a fade. Without a file it
/// draws a white tile of the same size, so the layout never jumps.
struct Thumbnail: View {
    /// The app's own previews draw this when there is no file (the widget never sets it).
    @MainActor static var previewImage: UIImage?
    var size: CGSize
    var corner: CGFloat
    private let theme = ActivityTheme.current
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        Group {
            if let image = (SharedContainer.thumbnailURL.flatMap { UIImage(contentsOfFile: $0.path) }) ?? Self.previewImage {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.white
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(theme.glassEdge, lineWidth: 1))
    }
}
