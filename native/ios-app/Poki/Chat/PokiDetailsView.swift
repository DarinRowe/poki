import SwiftUI

// The details screen opens from the header like iMessage's contact info (GetStream/swiftui-iMessage-clone,
// commit df114b4, iMessageClone/MessageList/View/Header/MessageListHeaderModifier.swift: a sheet from the
// header button). Its content is the ESP-171 board "M Poki details".

/// Poki's picture, name and what it does; Pause, Voice and History; the model; the status (the Poki
/// switch, relay, runner, last run and anything in the way); and voice, notifications and all settings.
struct PokiDetailsView: View {
    @Environment(AppModel.self) private var model
    @Environment(ChatModel.self) private var chat
    @Environment(\.dismiss) private var dismiss
    var openVoice: () -> Void
    var openSetup: () -> Void
    var start: [DetailsRoute] = []
    @State private var path: [DetailsRoute] = []
    @State private var sheet: DetailsSheet?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 0) {
                    HStack { Spacer(); Button("Done") { dismiss() }.font(.system(size: 17, weight: .semibold)).foregroundStyle(Site.blue) }
                        .padding(.horizontal, 20).padding(.top, 4)
                    header
                    actions.padding(.horizontal, 16).padding(.bottom, 22)
                    NavigationLink(value: DetailsRoute.model) { modelRow }
                        .buttonStyle(.plain)
                        .groupCard().padding(.horizontal, 16).padding(.bottom, 20)
                    GroupedSection(title: "STATUS") { status }
                        .padding(.horizontal, 16).padding(.bottom, 20)
                    VStack(spacing: 0) {
                        ChevronRow(title: "Voice and Speech") { sheet = .voice }
                        ChevronRow(title: "Notifications") { openNotificationSettings() }
                        ChevronRow(title: "All Settings", divider: false) { sheet = .settings([]) }
                    }
                    .groupCard().padding(.horizontal, 16).padding(.bottom, 32)
                }
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: DetailsRoute.self) { route in
                switch route {
                case .model: ModelSettingsView(openAgents: { sheet = .settings([]) })
                case .history: AllStepsView()
                }
            }
        }
        .onAppear { if path.isEmpty, !start.isEmpty { path = start } }
        .sheet(item: $sheet) { which in
            switch which {
            case .voice: VoiceView()
            case .settings(let start):
                SettingsView(start: start, openSetup: { sheet = nil; dismiss(); Task { try? await Task.sleep(for: .milliseconds(450)); openSetup() } })
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            PokiAvatar(size: 96)
            Text(verbatim: "Poki").font(.system(size: 28, weight: .semibold)).foregroundStyle(Color(.label))
            Text("Taps and types on this iPhone for you").font(.system(size: 15)).foregroundStyle(ChatColor.secondary)
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 16)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            // Pause: the task in the chat stops and the runner sleeps until the next request.
            if model.sessionOn && !model.runnerPaused || chat.running {
                ActionTile(title: "Pause", symbol: "pause.fill") { chat.stop(); model.pauseRunner() }
            } else {
                ActionTile(title: model.sessionOn ? "Resume" : "Turn On", symbol: "play.fill") {
                    if model.sessionOn { model.wakeRunner() } else { model.startSession() }
                }
            }
            ActionTile(title: "Voice", symbol: "mic.fill") { dismiss(); openVoice() }
            ActionTile(title: "History", symbol: "clock") { path.append(.history) }
        }
    }

    private var modelRow: some View {
        let provider = ModelKeys.selectedProvider
        let hasKey = ModelKeys.hasKey(provider)
        return HStack(spacing: 12) {
            ProviderTile(provider: provider, size: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text("Model").font(.system(size: 17)).foregroundStyle(Color(.label))
                Text(hasKey ? String(localized: "\(ModelKeys.selectedModelName), your \(provider.name) key") : String(localized: "Add your key to chat with Poki"))
                    .font(.system(size: 13)).foregroundStyle(hasKey ? ChatColor.secondary : Color(.systemOrange))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Chevron()
        }
        .padding(.vertical, 11).padding(.horizontal, 16)
        .contentShape(.rect)
        .id(ModelKeys.saved)
    }

    @ViewBuilder private var status: some View {
        let issues = Issue.current(model)
        Toggle(isOn: Binding(get: { model.sessionOn }, set: { $0 ? model.startSession() : model.stopSession() })) {
            Text(verbatim: "Poki").font(.system(size: 17))
        }
        .tint(ChatColor.green)
        .padding(.vertical, 6.5).padding(.horizontal, 16)
        .rowDivider()
        ValueRow(title: "Relay", health: Health.relay(model))
        ValueRow(title: "Runner", health: Health.runner(model), divider: model.recentSteps.last != nil || !issues.isEmpty)
        if model.recentSteps.last != nil {
            Button { path.append(.history) } label: {
                HStack {
                    Text("Last Run").font(.system(size: 17)).foregroundStyle(Color(.label))
                    Spacer()
                    Text(verbatim: "\(lastRun) ›").font(.system(size: 17)).foregroundStyle(ChatColor.secondary)
                }
                .padding(.vertical, 11).padding(.horizontal, 16).frame(minHeight: 44).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .rowDivider(!issues.isEmpty)
        }
        ForEach(Array(issues.enumerated()), id: \.element.id) { i, issue in
            IssueRow(issue: issue, openSetup: { dismiss(); openSetup() }).rowDivider(i < issues.count - 1)
        }
    }

    /// "Messages, 1:24": the app of the last run and how long it took.
    private var lastRun: String {
        let steps = model.recentSteps
        guard let first = steps.first, let last = steps.last else { return "" }
        let seconds = Int(last.at.timeIntervalSince(first.at))
        let time = String(format: "%d:%02d", seconds / 60, seconds % 60)
        return model.currentApp.map { "\($0), \(time)" } ?? time
    }

    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
    }
}

enum DetailsRoute: Hashable { case model, history }

private enum DetailsSheet: Identifiable {
    case voice, settings([SettingsRoute])
    var id: String { switch self { case .voice: "voice"; case .settings: "settings" } }
}

// MARK: Rows

/// A white group with 12 pt corners on the grouped grey (the boards' rows).
struct GroupCard: ViewModifier {
    func body(content: Content) -> some View {
        content.frame(maxWidth: .infinity).background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12, style: .continuous))
    }
}

extension View {
    func groupCard() -> some View { modifier(GroupCard()) }
    /// The 0.5 pt separator under a row, from the leading edge of the text.
    func rowDivider(_ show: Bool = true) -> some View {
        overlay(alignment: .bottom) { if show { ChatColor.separator.frame(height: 0.5) } }
    }
}

struct GroupedSection<Content: View>: View {
    var title: LocalizedStringKey
    var footer: LocalizedStringKey?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13)).foregroundStyle(Color(.secondaryLabel)).padding(.horizontal, 16)
            VStack(spacing: 0) { content }.groupCard()
            if let footer {
                Text(footer).font(.system(size: 13)).foregroundStyle(Color(.secondaryLabel)).padding(.horizontal, 16)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct Chevron: View {
    var body: some View { Text(verbatim: "›").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color(.tertiaryLabel)) }
}

private struct ChevronRow: View {
    var title: LocalizedStringKey
    var divider = true
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 17)).foregroundStyle(Color(.label))
                Spacer()
                Chevron()
            }
            .padding(.vertical, 11).padding(.horizontal, 16).frame(minHeight: 44).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .rowDivider(divider)
    }
}

private struct ValueRow: View {
    var title: LocalizedStringKey
    var health: Health
    var divider = true
    var body: some View {
        HStack {
            Text(title).font(.system(size: 17)).foregroundStyle(Color(.label))
            Spacer()
            HStack(spacing: 4) {
                Text(verbatim: "●").foregroundStyle(Self.dot(health.color))
                Text(health.word)
            }
            .font(.system(size: 17)).foregroundStyle(ChatColor.secondary)
        }
        .padding(.vertical, 11).padding(.horizontal, 16).frame(minHeight: 44)
        .rowDivider(divider)
        .accessibilityElement(children: .combine)
    }

    /// Health's dots are drawn for the blue page; on white, green is iOS green, red iOS red, and the
    /// white and faded ones grey (#C7C7CC on the board).
    static func dot(_ color: Color) -> Color {
        if color == Site.ok { return ChatColor.green }
        if color == Site.bad { return Color(.systemRed) }
        return Color(.systemGray3)
    }
}

private struct IssueRow: View {
    @Environment(AppModel.self) private var model
    var issue: Issue
    var openSetup: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) { Text(verbatim: "●").foregroundStyle(Color(.systemRed)); Text(issue.title) }
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(.label))
            Text(issue.text).font(.system(size: 15)).foregroundStyle(ChatColor.secondary).fixedSize(horizontal: false, vertical: true)
            if let button = issue.button {
                Button { issue.act(model, openSetup: openSetup) } label: { Text(button).font(.system(size: 15, weight: .semibold)).foregroundStyle(Site.blue) }
                    .buttonStyle(.plain).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 11).padding(.horizontal, 16)
    }
}

private struct ActionTile: View {
    var title: LocalizedStringKey
    var symbol: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 18, weight: .medium)).frame(width: 22, height: 22)
                Text(title).font(.system(size: 12))
            }
            .foregroundStyle(Site.blue)
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// The provider's letter on its coloured tile.
struct ProviderTile: View {
    var provider: ModelProvider
    var size: CGFloat = 29
    var body: some View {
        Text(verbatim: provider.mark)
            .font(.system(size: provider == .custom ? 11 : 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hex: provider.tile), in: .rect(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}
