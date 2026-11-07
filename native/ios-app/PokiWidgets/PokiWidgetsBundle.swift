// The Live Activity's configuration follows AgentLiveActivityWidget in Clarklevis1995/dsh-mobile
// (commit ebe19764, AgentLiveActivityWidget/AgentLiveActivityWidget.swift), MIT License, Copyright (c)
// 2026 Chaofan Li. See THIRD_PARTY_NOTICES.md.
import ActivityKit
import SwiftUI
import WidgetKit

@main
struct PokiWidgetsBundle: WidgetBundle {
    var body: some Widget { PokiLiveActivity() }
}

/// Poki's Live Activity: what the agent is doing and how its steps went, the pairing code while
/// pairing, the current setup step while setting up, and Allow/Deny for sensitive actions. The
/// buttons are for the person; PokiCore sends no input while an approval waits, so the runner never
/// taps them.
///
/// The Lock Screen card is the website's blue with white text and a glass edge; the Dynamic Island
/// stays black, with the website's light blue for its accents.
struct PokiLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PokiActivityAttributes.self) { context in
            LockScreenCard(state: context.shown)
                .activityBackgroundTint(ActivityTheme.current.lockBackground)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.shown
            let insets = ActivityMetrics.islandInsets
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { IslandLeading(state: state) }
                DynamicIslandExpandedRegion(.trailing) { IslandTrailing(state: state) }
                DynamicIslandExpandedRegion(.bottom) { IslandBottom(state: state) }
            } compactLeading: {
                CompactLeading(state: state)
            } compactTrailing: {
                CompactTrailing(state: state)
            } minimal: {
                MinimalView(state: state)
            }
            // The outline goes blue while an approval waits; otherwise the system's own.
            .keylineTint(state.face.outlined ? ActivityTheme.current.approvalOutline : nil)
            // The board's margins. iOS clips the corners tighter, so the rows inside move further in
            // where they reach them (ActivityMetrics.islandRowInset and the rest).
            .contentMargins(.leading, insets.leading, for: .expanded)
            .contentMargins(.trailing, insets.trailing, for: .expanded)
            .contentMargins(.top, insets.top, for: .expanded)
            .contentMargins(.bottom, insets.bottom, for: .expanded)
        }
    }
}

extension ActivityViewContext<PokiActivityAttributes> {
    /// The state to draw. An approval's stale date is its expiry: once it passes, the buttons go
    /// even if the app has not had a chance to update yet, so nobody taps Allow on a dead request.
    var shown: PokiState {
        var state = self.state
        if isStale, state.approval != nil {
            state.approval = nil
            state.decision = nil
            state.phase = .working
            state.headline = String(localized: "The approval timed out")
            state.event = .init(kind: .expired, text: String(localized: "Timed out"))
        }
        return state
    }
}
