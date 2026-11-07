import SwiftUI

// MARK: All steps

/// Every recent step, newest first, on a white card (board 01, D).
struct AllStepsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SitePage {
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: { HStack(spacing: 4) { Text(verbatim: "‹"); Text(verbatim: "Poki") }.site(17, line: 22) }
                        .buttonStyle(.plain).frame(width: 52, alignment: .leading)
                    Spacer()
                    Text("All Steps").site(17, .semibold, line: 22)
                    Spacer()
                    Color.clear.frame(width: 52, height: 1)
                }
                .frame(height: 44).padding(.horizontal, 16)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.currentApp ?? String(localized: "All Steps")).site(28, .heavy, line: 34, tracking: -0.02)
                        if let first = model.recentSteps.first {
                            Text("\(Self.stepCount(model)). Started at \(first.at.formatted(date: .omitted, time: .shortened)).")
                                .site(15, line: 20).foregroundStyle(Site.c3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)

                    Group {
                        if rows.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "clock").font(.system(size: 16)).foregroundStyle(Site.text3)
                                Text("Steps from your agent appear here and on the Lock Screen.").site(15, line: 20)
                                    .foregroundStyle(Site.text2).multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 28).padding(.horizontal, 16)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                                    StepRow(row: row, last: i == rows.count - 1)
                                }
                            }
                            .padding(16)
                        }
                    }
                    .whiteCard()
                    .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 24)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    /// "12 steps", or "12 steps, 1 missed".
    @MainActor static func stepCount(_ model: AppModel) -> String {
        let steps = model.recentSteps
        let missed = steps.filter { !$0.ok }.count
        let count = String(localized: "\(steps.count + (model.activityText != "Idle" ? 1 : 0)) steps")
        return missed == 0 ? count : String(localized: "\(count), \(missed) missed")
    }

    struct Row {
        var text: String
        var detail: String
        var failed: Bool
        var at: Date
    }

    /// The step under way (waiting for approval or working) first, then the finished ones.
    private var rows: [Row] {
        var out: [Row] = []
        if model.activityText != "Idle" {
            out.append(Row(text: model.activityText, detail: model.approvals.isEmpty ? String(localized: "Working") : String(localized: "Waiting for Approval"),
                           failed: false, at: Date()))
        }
        for step in model.recentSteps.reversed() {
            let failure = step.failure.map { Bundle.main.localizedString(forKey: $0, value: $0, table: nil) }.map { $0.prefix(1).uppercased() + $0.dropFirst() }
            out.append(Row(text: step.text, detail: failure ?? step.app ?? String(localized: "Done"), failed: !step.ok, at: step.at))
        }
        return out
    }
}

private struct StepRow: View {
    var row: AllStepsView.Row
    var last: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Image(systemName: row.failed ? "xmark" : Self.symbol(for: row.text))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(row.failed ? Site.bad : Site.blue)
                    .frame(width: 30, height: 30)
                    .background(row.failed ? Color(hex: 0xFFECEB) : Site.tint, in: .circle)
                if !last { Site.hair.frame(width: 1.5).frame(maxHeight: .infinity) }
            }
            .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ActivityWords.label(row.text)).site(15, .medium, line: 20).foregroundStyle(Site.text).lineLimit(2)
                    Spacer(minLength: 8)
                    Text(row.at, style: .time).site(12, line: 16).monospacedDigit().foregroundStyle(Site.text3)
                }
                Text(row.detail).site(13, line: 18).foregroundStyle(row.failed ? Site.text : Site.text2).lineLimit(2)
            }
            .padding(.bottom, last ? 0 : 16)
        }
    }

    static func symbol(for text: String) -> String {
        let verb = text.split(separator: " ").first.map(String.init) ?? ""
        switch verb {
        case "Tap": return "hand.tap"
        case "Press": return text.hasSuffix("button") ? "button.horizontal.top.press" : "keyboard"
        case "Type": return "character.cursor.ibeam"
        case "Swipe", "Scroll": return "hand.draw"
        case "Drag": return "hand.point.up.left"
        case "Zoom": return "arrow.up.left.and.arrow.down.right"
        case "Open": return "app.badge"
        case "Look": return "eye"
        case "Wait": return "hourglass"
        default: return "sparkles"
        }
    }
}
