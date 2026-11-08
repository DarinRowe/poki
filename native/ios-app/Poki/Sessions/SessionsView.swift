import SwiftUI
import UIKit

/// Poki's home: every conversation, like the Messages list. The owner's chats with Poki, the sessions of
/// outside agents (Claude, Codex, any MCP client) and the tasks they handed to Poki, live first. On top,
/// a strip with one half for each way of using Poki: the address agents connect to, and Poki's own model.
struct SessionsView: View {
    @Environment(AppModel.self) private var model
    @Environment(ChatModel.self) private var chat
    var openChat: () -> Void
    var openSession: (String) -> Void
    var openModel: () -> Void
    var openConnectors: () -> Void
    var openDetails: () -> Void
    var openVoice: () -> Void
    var openSetup: () -> Void
    @State private var copied = false
    @State private var query = ""
    @State private var renaming: SavedSession?
    @State private var newName = ""

    private var store: SessionStore { SessionStore.shared }

    var body: some View {
        List {
            // What matters before any conversation: whether Poki is on, whether agents can reach it,
            // and what setup still needs.
            Section {
                // Every setup item still open, each straight to its fix.
                ForEach(SetupStep.shown.filter { !model.isDone($0) && $0 != .loopback }) { step in
                    NavigationLink(value: step) { SetupStepRow(step: step) }
                }
                if !ModelKeys.hasUsableKey {
                    Button(action: openModel) {
                        Label("Add a Model Key to Chat", systemImage: "key.fill")
                    }
                }
            }
            if store.ordered.isEmpty {
                // In the list, under the controls (an overlay would sit on top of them).
                Section {
                    ContentUnavailableView {
                        Label("No Sessions Yet", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("Start a chat with Poki, or connect an agent such as Claude or Codex in Agents. Every session shows up here.")
                    }
                    .listRowBackground(Color.clear)
                }
            }
            Section {
                ForEach(shown) { session in
                    Button { open(session) } label: { SessionRow(session: session) }
                        .buttonStyle(.plain)
                        .swipeActions {
                            if !session.live {
                                Button(role: .destructive) { store.delete(session.id) } label: { Label("Delete", systemImage: "trash") }
                            }
                            Button { startRename(session) } label: { Label("Rename", systemImage: "pencil") }
                                .tint(.blue)
                        }
                        .contextMenu {
                            Button { startRename(session) } label: { Label("Rename", systemImage: "pencil") }
                            if !session.live {
                                Button(role: .destructive) { store.delete(session.id) } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                }
            }
            if !query.isEmpty, shown.isEmpty {
                ContentUnavailableView.search(text: query).listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search Sessions"))
        .navigationTitle(Text(verbatim: "Poki"))
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            // Indicators left of the power button: the local connection and the agents' relay, each
            // green when working and grey (or orange) with a slashed icon when not; a tap opens its page.
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink(value: SetupStep.loopback) {
                    Image(systemName: model.loopback.isWorking ? "network" : "network.slash")
                        .foregroundStyle(model.loopback.isWorking ? Color.green : Color.orange)
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(Text(model.loopback.isWorking ? "Local connection on" : "Local connection off"))
                Button(action: openConnectors) {
                    Image(systemName: agentsIcon.0)
                        .foregroundStyle(agentsIcon.1)
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(Text("Agents: \(agentsLine)"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                PowerButton(on: model.sessionOn, turnOn: { model.startSession() }, turnOff: { chat.stop(); model.stopSession() })
            }
        }
        .alert("Rename Session", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let session = renaming { store.rename(session.id, to: newName) }
                renaming = nil
            }
        }
        // A new chat with Poki's own agent, at the bottom left.
        .safeAreaInset(edge: .bottom, alignment: .leading, spacing: 0) {
            Button { chat.newConversation(); openChat() } label: {
                Image(systemName: "square.and.pencil").font(.title3.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .newChatStyle()
            .controlSize(.large)
            .fixedSize()
            .disabled(chat.running)
            .padding(.leading, 16).padding(.bottom, 8)
            .accessibilityLabel(Text("New Chat with Poki"))
        }
    }

    /// "Working in Messages", "Ready", "Off".
    private var runLine: String {
        if chat.running { return model.currentApp.map { String(localized: "Working in \($0)") } ?? String(localized: "Working") }
        if !model.sessionOn { return String(localized: "Off. Agents and chats can’t use this iPhone.") }
        if model.runnerPaused { return String(localized: "Paused") }
        return String(localized: "On, ready for a task")
    }

    /// The agents indicator: online green, connecting yellow, otherwise grey and slashed.
    private var agentsIcon: (String, Color) {
        switch model.relayStatus {
        case .ready: ("person.2.wave.2.fill", .green)
        case .connecting: ("person.2.wave.2", .yellow)
        case .offline: ("person.2.slash", .orange)
        case .off: ("person.2.slash", .secondary)
        }
    }

    private var agentsLine: String {
        let live = SessionStore.shared.liveAgentCount
        switch model.relayStatus {
        case .ready: return live > 0 ? String(localized: "Online · \(live) live") : String(localized: "Online")
        case .connecting: return String(localized: "Connecting")
        case .offline: return String(localized: "Offline")
        case .off: return model.identity.secrets.isEmpty ? String(localized: "None yet") : String(localized: "Off")
        }
    }

    private var needsSetup: Bool { model.pairingPath == nil || model.setupStepsLeft }

    /// The sessions matching the search field: name, first message or last line.
    private var shown: [SavedSession] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.ordered }
        return store.ordered.filter { [$0.name, $0.title, $0.lastLine, $0.client ?? ""].contains { $0.localizedCaseInsensitiveContains(q) } }
    }

    private func startRename(_ session: SavedSession) {
        newName = session.name
        renaming = session
    }

    private func open(_ session: SavedSession) {
        if session.kind == .poki {
            if session.id != chat.sessionID { chat.restore(session) }
            openChat()
        } else {
            openSession(session.id)
        }
    }

}

private extension View {
    /// Blue-tinted Liquid Glass on iOS 26 and later; a blue prominent capsule before it.
    @ViewBuilder func newChatStyle() -> some View {
        if #available(iOS 26.0, *) { buttonStyle(.glassProminent).buttonBorderShape(.circle).tint(.blue) }
        else { buttonStyle(.borderedProminent).buttonBorderShape(.circle).tint(.blue) }
    }
}

/// Poki's power, at the top right of the Poki tab: a plain toolbar button (the bar draws the glass),
/// the filled green power symbol while on, the grey outline while off. A tap turns it on or off, with
/// a haptic for each.
struct PowerButton: View {
    var on: Bool
    var turnOn: () -> Void
    var turnOff: () -> Void

    var body: some View {
        Button {
            if on {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                turnOff()
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                turnOn()
            }
        } label: {
            Image(systemName: on ? "power.circle.fill" : "power.circle")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(on ? Color.green : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityLabel(Text(on ? "Turn Poki Off" : "Turn Poki On"))
        .accessibilityValue(Text(on ? "On" : "Off"))
    }
}

/// One row: who, when, the last thing that happened, and how it ended.
struct SessionRow: View {
    var session: SavedSession

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SessionAvatar(session: session, size: 44)
                .overlay(alignment: .topTrailing) {
                    if session.live {
                        Circle().fill(ChatColor.green).frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
                            .offset(x: 2, y: -2)
                            .accessibilityLabel(Text("Live"))
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: session.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Color(.label)).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(session.live ? String(localized: "now") : ChatTime.row(session.updated)).font(.system(size: 15)).foregroundStyle(ChatColor.secondary)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(.tertiaryLabel))
                }
                HStack(spacing: 4) {
                    outcomeMark
                    Text(verbatim: subtitle).font(.system(size: 15)).foregroundStyle(ChatColor.secondary).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let line = session.lastLine
        if session.kind != .poki, line.isEmpty { return session.title }
        return line
    }

    @ViewBuilder private var outcomeMark: some View {
        switch session.outcome {
        case .failed?: Image(systemName: "exclamationmark.circle.fill").font(.system(size: 13)).foregroundStyle(Color(.systemOrange))
        case .stopped?: Image(systemName: "pause.circle.fill").font(.system(size: 13)).foregroundStyle(ChatColor.secondary)
        default: EmptyView()
        }
    }
}

/// Poki's bear for its own chats; the agent's initial on its colour for an outside agent; both for a
/// hand-off.
struct SessionAvatar: View {
    var session: SavedSession
    var size: CGFloat

    var body: some View {
        switch session.kind {
        case .poki: PokiAvatar(size: size)
        case .agent: AgentBadge(name: session.client ?? "", size: size)
        case .handoff:
            ZStack(alignment: .bottomTrailing) {
                AgentBadge(name: session.client ?? "", size: size)
                PokiAvatar(size: size * 0.5).overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
                    .offset(x: 3, y: 3)
            }
        }
    }
}

struct AgentBadge: View {
    var name: String
    var size: CGFloat
    var body: some View {
        Group {
            if let logo {
                Image(logo).resizable().renderingMode(.template).scaledToFit()
                    .frame(width: size * 0.52, height: size * 0.52)
            } else {
                Text(verbatim: initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            }
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(Color(hex: tint), in: .circle)
        .accessibilityHidden(true)
    }
    /// The provider's own logo (Poki/ProviderIcons) for agents that run on it.
    private var logo: String? {
        let n = name.lowercased()
        if n.contains("claude") || n.contains("anthropic") { return "Provider-anthropic" }
        if n.contains("codex") || n.contains("chatgpt") || n.contains("openai") { return "Provider-openai" }
        if n.contains("gemini") { return "Provider-googlegemini" }
        if n.contains("deepseek") { return "Provider-deepseek" }
        if n.contains("openrouter") { return "Provider-openrouter" }
        return nil
    }
    private var initials: String {
        let words = name.split(separator: " ")
        if words.count >= 2 { return String(words[0].prefix(1) + words[1].prefix(1)).uppercased() }
        return String(name.prefix(1)).uppercased()
    }
    /// The provider tiles' colours where they match, a calm grey otherwise.
    private var tint: UInt32 {
        let n = name.lowercased()
        if n.contains("claude") { return 0xD97757 }
        if n.contains("codex") || n.contains("chatgpt") { return 0x10A37F }
        if n.contains("gemini") { return 0x4285F4 }
        if n.contains("cursor") { return 0x111111 }
        return 0x8E8E93
    }
}

/// An outside agent's session or hand-off as a conversation: the agent's own steps as grey lines, its
/// request and Poki's answer as bubbles. Live while the session runs.
struct SessionView: View {
    @Environment(AppModel.self) private var model
    var id: String
    var back: () -> Void
    var hidesTabBar = true

    var body: some View {
        let session = SessionStore.shared.session(id)
        VStack(spacing: 0) {
            ChatTranscript(entries: (AskPoki.live(id)?.entries ?? session?.entries) ?? [], typing: AskPoki.live(id)?.awaitingModel ?? false, canRetry: false, retry: {}) {
                if session?.live == true, let approval = model.approvals.first {
                    ApprovalCard(approval: approval) { approved in model.resolve(approval, approved: approved) }
                }
            }
            if AskPoki.live(id) != nil {
                Button("Stop Poki") { AskPoki.live(id)?.stop() }.buttonStyle(.bordered).tint(Color(.systemRed)).padding(.bottom, 10)
            }
        }
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(verbatim: session?.name ?? "").font(.headline)
                    Text(verbatim: caption(session)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .toolbar(hidesTabBar ? .hidden : .automatic, for: .tabBar)
    }

    private func caption(_ session: SavedSession?) -> String {
        guard let session else { return "" }
        switch session.kind {
        case .agent: return String(localized: "Over MCP · \(ChatTime.row(session.started))")
        case .handoff: return String(localized: "Handed to Poki · \(ChatTime.row(session.started))")
        case .poki: return ""
        }
    }
}

/// An approval waiting for the owner, inside the session that asked for it (also in the Dynamic Island).
private struct ApprovalCard: View {
    var approval: PendingApproval
    var answer: (Bool) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Allow this step?").font(.system(size: 15, weight: .semibold))
            Text(verbatim: approval.summary).font(.system(size: 15)).foregroundStyle(Color(.label))
            HStack {
                Button("Don’t Allow") { answer(false) }.buttonStyle(.bordered)
                Button("Allow") { answer(true) }.buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16, style: .continuous))
        .padding(.top, 8)
    }
}
