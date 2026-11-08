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

    private var store: SessionStore { SessionStore.shared }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    strip.listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16)).listRowSeparator(.hidden)
                    if needsSetup { setupRow.listRowSeparator(.hidden) }
                }
                Section {
                    if store.ordered.isEmpty {
                        empty.listRowSeparator(.hidden)
                    }
                    ForEach(store.ordered) { session in
                        Button { open(session) } label: { SessionRow(session: session) }
                            .buttonStyle(.plain)
                            .swipeActions {
                                if !session.live {
                                    Button(role: .destructive) { store.delete(session.id) } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(Text("Sessions"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: openDetails) { PokiAvatar(size: 30) }.accessibilityLabel(Text("Poki, details"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { chat.newConversation(); openChat() } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel(Text("New chat with Poki"))
                        .disabled(chat.running)
                }
            }
        }
        .background(Color(.systemBackground))
    }

    private var needsSetup: Bool { (model.pairingPath == nil || model.setupStepsLeft) && !model.sessionOn && SessionStore.shared.sessions.isEmpty }

    private func open(_ session: SavedSession) {
        if session.kind == .poki {
            if session.id != chat.sessionID { chat.restore(session) }
            openChat()
        } else {
            openSession(session.id)
        }
    }

    // MARK: Strip

    /// Two cards side by side: for people whose agents drive Poki, and for people who talk to Poki.
    private var strip: some View {
        HStack(alignment: .top, spacing: 10) {
            StripCard(title: "For your agents", symbol: "point.3.connected.trianglepath.dotted") {
                Text(agentsLine).foregroundStyle(ChatColor.secondary)
                if let url = connectorURL {
                    Button(copied ? "Copied" : "Copy MCP Address") {
                        UIPasteboard.general.string = url
                        copied = true
                        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                    }
                    .fontWeight(.semibold)
                } else {
                    Button("Connect an Agent", action: openConnectors).fontWeight(.semibold)
                }
            }
            StripCard(title: "Poki’s own agent", symbol: "bubble.left.and.text.bubble.right") {
                Text(modelLine).foregroundStyle(ChatColor.secondary).lineLimit(1)
                Button(ModelKeys.hasUsableKey ? "Change Model" : "Add a Key", action: openModel).fontWeight(.semibold)
            }
        }
        .font(.system(size: 13))
    }

    private var connectorURL: String? {
        model.identity.secrets.first.flatMap { model.connectorURL(for: $0)?.absoluteString }
    }

    private var agentsLine: String {
        let live = SessionStore.shared.liveAgentCount
        switch model.relayStatus {
        case .ready: return live > 0 ? String(localized: "Online · \(live) live") : String(localized: "Online")
        case .connecting: return String(localized: "Connecting")
        case .offline: return String(localized: "Offline")
        case .off: return model.identity.secrets.isEmpty ? String(localized: "No agent yet") : String(localized: "Off")
        }
    }

    private var modelLine: String {
        ModelKeys.hasUsableKey ? ModelKeys.selectedModelName : String(localized: "Not set up")
    }

    private var setupRow: some View {
        Button(action: openSetup) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(Site.blue)
                Text(model.pairingPath != nil ? "Finish setting up this iPhone." : "First, set up this iPhone. About 5 minutes.").foregroundStyle(Color(.label))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(ChatColor.secondary)
            }
            .font(.system(size: 15))
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 28)).foregroundStyle(ChatColor.secondary)
            Text("No sessions yet").font(.system(size: 17, weight: .semibold))
            Text("Chat with Poki, or connect an agent such as Claude or Codex. Every session shows up here.")
                .font(.system(size: 15)).foregroundStyle(ChatColor.secondary).multilineTextAlignment(.center)
            Button("Message Poki") { openChat() }.buttonStyle(.borderedProminent).tint(Site.blue).padding(.top, 6)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 36).padding(.horizontal, 16)
    }
}

private struct StripCard<Content: View>: View {
    var title: LocalizedStringKey
    var symbol: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(.label)).lineLimit(1)
            content()
        }
        .tint(Site.blue)
        .buttonStyle(.plain)
        .foregroundStyle(Site.blue)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14, style: .continuous))
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
        Text(verbatim: initials)
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hex: tint), in: .circle)
            .accessibilityHidden(true)
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

    var body: some View {
        let session = SessionStore.shared.session(id)
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                if let session { SessionAvatar(session: session, size: 56) }
                Text(verbatim: session?.name ?? "").font(.system(size: 12)).foregroundStyle(Color(.label))
                Text(verbatim: caption(session)).font(.system(size: 11)).foregroundStyle(ChatColor.secondary)
            }
            .padding(.top, 2).padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topLeading) {
                Button(action: back) {
                    Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold)).foregroundStyle(Site.blue).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain).padding(.leading, 6).accessibilityLabel(Text("Sessions"))
            }
            .background { Rectangle().fill(.bar).ignoresSafeArea(edges: .top).overlay(alignment: .bottom) { ChatColor.separator.frame(height: 0.5) } }
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
        .toolbar(.hidden, for: .navigationBar)
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
                Button("Allow") { answer(true) }.buttonStyle(.borderedProminent).tint(Site.blue)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16, style: .continuous))
        .padding(.top, 8)
    }
}
