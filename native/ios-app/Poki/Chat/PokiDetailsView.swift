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
    /// Shown as the Status tab: no Done button, a large title instead.
    var inTab = false
    @State private var path: [DetailsRoute] = []
    @State private var sheet: DetailsSheet?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    let issues = Issue.current(model)
                    Toggle("Poki", isOn: Binding(get: { model.sessionOn }, set: { $0 ? model.startSession() : model.stopSession() }))
                    // The in-process path has no Poki Runner (ESP-152): its row is hidden, the code kept.
                    HealthRow(title: "Relay", health: Health.relay(model))
                    if model.automationPath == .runner { HealthRow(title: "Runner", health: Health.runner(model)) }
                    if model.recentSteps.last != nil {
                        NavigationLink(value: DetailsRoute.history) { LabeledContent("Last Run", value: lastRun) }
                    }
                    if model.sessionOn && !model.runnerPaused || chat.running {
                        Button("Pause", systemImage: "pause.fill") { chat.stop(); model.pauseRunner() }
                    } else if model.sessionOn {
                        Button("Resume", systemImage: "play.fill") { model.wakeRunner() }
                    }
                    ForEach(issues) { issue in
                        IssueRow(issue: issue, openSetup: { if !inTab { dismiss() }; openSetup() })
                    }
                } header: {
                    Text("Status")
                }

                Section {
                    NavigationLink(value: DetailsRoute.model) {
                        let provider = ModelKeys.selectedProvider
                        let hasKey = ModelKeys.hasKey(provider)
                        LabeledContent {
                            Text(hasKey ? ModelKeys.selectedModelName : String(localized: "Add Key")).foregroundStyle(hasKey ? Color.secondary : Color.orange)
                        } label: {
                            Label { Text("Model") } icon: { ProviderTile(provider: provider, size: 29) }
                        }
                    }
                    .id(ModelKeys.saved)
                    Button { if !inTab { dismiss() }; openVoice() } label: { Label("Start Live Voice", systemImage: "waveform") }
                    Button { sheet = .voice } label: { Label("Voice and Speech", systemImage: "speaker.wave.2") }
                    NavigationLink(value: DetailsRoute.history) { Label("History", systemImage: "clock") }
                }

                Section {
                    Button { openNotificationSettings() } label: { Label("Notifications", systemImage: "bell.badge") }
                    Button { sheet = .settings([]) } label: { Label("Settings", systemImage: "gear") }
                    Button { if !inTab { dismiss() }; openSetup() } label: { Label("Setup", systemImage: "checklist") }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(Text(verbatim: "Poki"))
            .navigationBarTitleDisplayMode(inTab ? .large : .inline)
            .toolbar {
                if !inTab { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
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
                SettingsView(start: start, openSetup: { sheet = nil; if !inTab { dismiss() }; Task { try? await Task.sleep(for: .milliseconds(450)); openSetup() } })
            }
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

private struct HealthRow: View {
    var title: LocalizedStringKey
    var health: Health
    var body: some View {
        LabeledContent(title) {
            Label { Text(health.word) } icon: { Image(systemName: "circle.fill").font(.system(size: 9)).foregroundStyle(ValueRow.dot(health.color)) }
        }
    }
}

private struct IssueRow: View {
    @Environment(AppModel.self) private var model
    var issue: Issue
    var openSetup: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(issue.title, systemImage: "exclamationmark.triangle.fill").font(.subheadline.weight(.semibold))
                .symbolRenderingMode(.multicolor)
            Text(issue.text).font(.subheadline).foregroundStyle(.secondary)
            if let button = issue.button {
                Button(button) { issue.act(model, openSetup: openSetup) }.font(.subheadline.weight(.semibold)).buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 2)
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
