import SwiftUI

/// The chat page (ESP-171 boards "M Chat empty", "M Chat working", "M Chat approved"): Poki's picture and
/// name on top, the bubbles, and the message field. Approvals happen in the Dynamic Island; the chat only
/// keeps one grey line about them.
struct ChatView: View {
    @Environment(AppModel.self) private var model
    @Environment(ChatModel.self) private var chat
    var openDetails: () -> Void
    var openVoice: () -> Void
    var openSetup: () -> Void
    var openModel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            MessageListHeader(dark: false, openDetails: openDetails)
            ScrollView {
                VStack(spacing: 4) {
                    Spacer(minLength: 0)
                    ForEach(Array(chat.entries.enumerated()), id: \.element.id) { i, entry in
                        row(entry, at: i).id(entry.id)
                    }
                    if needsSetup { SetupBubble(paired: model.pairingPath != nil, openSetup: openSetup) }
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
                .frame(maxWidth: .infinity)
                .containerRelativeFrame(.vertical, alignment: .bottom) { height, _ in height }
                .animation(PlanMotion.enter, value: chat.entries)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            ComposerInputView(running: chat.running, send: chat.send, stop: chat.stop, openVoice: openVoice, openModel: openModel, newConversation: chat.newConversation)
            ModeLabels(page: .chat, dark: false)
        }
        .background(Color(.systemBackground))
    }

    /// Setup is not finished (nothing paired yet, or a step left after pairing, such as UI Automation):
    /// the chat says so, one tap from setup, as the old Home's Setup row did.
    private var needsSetup: Bool { (model.pairingPath == nil || model.setupStepsLeft) && !model.sessionOn && !chat.running && !chat.isSample }

    @ViewBuilder private func row(_ entry: ChatEntry, at i: Int) -> some View {
        switch entry.kind {
        case .time(let date):
            Text("\(Text("Today").fontWeight(.semibold)) \(date.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 12)).foregroundStyle(ChatColor.secondary)
                .padding(.bottom, 6).frame(maxWidth: .infinity)
        case .you(let text, let delivered):
            let last = isLast(i, poki: false)
            VStack(alignment: .trailing, spacing: 4) {
                MessageBubble(direction: .outgoing, text: text, tail: last)
                if last, delivered {
                    Text("Delivered").font(.system(size: 11, weight: .medium)).foregroundStyle(ChatColor.secondary)
                        .padding(.horizontal, 4).padding(.bottom, 8)
                        .transition(.opacity)
                }
            }
            .padding(.top, startsRun(i) ? 10 : 0)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        case .poki(let text):
            MessageBubble(direction: .incoming, text: text, tail: isLast(i, poki: true))
                .padding(.top, startsRun(i) ? 10 : 0)
                .transition(PlanMotion.stepTransition)
        case .plan(let steps):
            HStack {
                PlanBubble(steps: steps, tail: isLast(i, poki: true))
                Spacer(minLength: .messageInsetPadding)
            }
            .padding(.top, startsRun(i) ? 10 : 0)
            .transition(PlanMotion.stepTransition)
        case .note(let note):
            NoteLine(note: note)
        }
    }

    /// The last bubble from that side in the conversation has the small corner (the boards).
    private func isLast(_ i: Int, poki: Bool) -> Bool {
        !chat.entries[(i + 1)...].contains { entry in
            switch entry.kind {
            case .poki, .plan: poki
            case .you: !poki
            default: false
            }
        }
    }

    /// A bubble after the other side's (or the time) leaves 10 pt more.
    private func startsRun(_ i: Int) -> Bool {
        guard i > 0 else { return false }
        let mine = chat.entries[i].isPoki
        for entry in chat.entries[..<i].reversed() {
            switch entry.kind {
            case .note: continue
            case .time: return false
            default: return entry.isPoki != mine
            }
        }
        return false
    }
}

// MARK: Header

// MessageListHeader is from GetStream/swiftui-iMessage-clone (commit df114b4,
// iMessageClone/MessageList/View/Header/MessageListHeader.swift, by Stefan Blos; the repository has no
// licence file). Changed: Poki's picture at the board's 56 pt instead of 20, the 12 pt name with its
// chevron, no video button, and a view of its own instead of a toolbar item.
struct MessageListHeader: View {
    var dark: Bool
    var openDetails: () -> Void

    var body: some View {
        Button(action: openDetails) {
            VStack(spacing: 4) {
                PokiAvatar(size: 56)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: "Poki")
                        .font(.system(size: 12))
                        .foregroundStyle(dark ? Color.white : Color(.label))
                    Image(systemName: "chevron.right")
                        .resizable()
                        .scaledToFit()
                        .fontWeight(.semibold)
                        .frame(width: 5, height: 8)
                        .foregroundStyle(dark ? Color.white.opacity(0.7) : ChatColor.secondary)
                }
            }
            .padding(.top, 2).padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Poki, details"))
        .background {
            if !dark {
                Rectangle().fill(.bar).ignoresSafeArea(edges: .top)
                    .overlay(alignment: .bottom) { ChatColor.separator.frame(height: 0.5) }
            }
        }
    }
}

/// The bear in a round frame, as the ESP-171 boards draw it (`PokiFace.png` is the boards' own image: the
/// app icon's bear, closer up).
struct PokiAvatar: View {
    var size: CGFloat
    static let face = UIImage(named: "PokiFace")
    var body: some View {
        Group {
            if let face = Self.face { Image(uiImage: face).resizable().scaledToFill() } else { Image("Bear").resizable().scaledToFill() }
        }
        .frame(width: size, height: size).clipShape(.circle)
        .accessibilityHidden(true)
    }
}

// MARK: Plan

/// The steps of a task in one Poki bubble: done steps ticked, the step under way typing its words.
struct PlanBubble: View {
    var steps: [PlanStep]
    var tail: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(steps) { step in
                PlanRow(step: step).transition(PlanMotion.stepTransition)
            }
        }
        .animation(PlanMotion.enter, value: steps)
        .padding(.vertical, 10).padding(.horizontal, 14)
        .frame(width: 250, alignment: .leading)
        .background(ChatColor.incoming, in: UnevenRoundedRectangle(topLeadingRadius: .cornerRadius, bottomLeadingRadius: tail ? .tailRadius : .cornerRadius,
                                                                    bottomTrailingRadius: .cornerRadius, topTrailingRadius: .cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct PlanRow: View {
    var step: PlanStep

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            ZStack {
                switch step.state {
                case .done:
                    DrawingCheck(color: ChatColor.green).frame(width: 12, height: 12).transition(PlanMotion.swapTransition)
                case .failed:
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(.systemRed)).transition(PlanMotion.swapTransition)
                case .current, .waiting:
                    Circle().strokeBorder(ChatColor.secondary.opacity(0.6), lineWidth: 1).frame(width: 13, height: 13).transition(PlanMotion.swapTransition)
                }
            }
            .frame(width: 13)
            .animation(PlanMotion.swap, value: step.state)
            Group {
                switch step.state {
                case .current, .waiting:
                    TypewriterText(text: step.state == .waiting ? String(localized: "\(step.text), waiting for you") : step.text,
                                   font: .system(size: 15), color: ChatColor.pending)
                case .done, .failed:
                    Text(step.text).font(.system(size: 15)).foregroundStyle(Color(.label))
                        .transition(PlanMotion.swapTransition.animation(PlanMotion.swap.delay(PlanMotion.stagger)))
                }
            }
            .animation(PlanMotion.complete, value: step.state)
        }
        .lineLimit(2)
    }
}

// MARK: Notes

/// One grey line about an approval, centred under the steps.
private struct NoteLine: View {
    var note: ChatNote
    var body: some View {
        HStack(spacing: 6) {
            switch note {
            case .waiting:
                // The Dynamic Island, small.
                Capsule().fill(Color(hex: 0x1C1C1E)).frame(width: 22, height: 8)
                Text("Waiting for you to approve in the Dynamic Island")
            case .approved(let at):
                Text(verbatim: "✓").fontWeight(.semibold).foregroundStyle(ChatColor.green)
                Text("Approved in the Dynamic Island, \(at.formatted(date: .omitted, time: .shortened))")
            case .declined:
                Text(verbatim: "✕").fontWeight(.semibold).foregroundStyle(Color(.systemRed))
                Text("Not approved, so Poki skipped that step")
            case .expired:
                Text("The approval ran out, so Poki skipped that step")
            case .problem(let text):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(.systemOrange))
                Text(text)
            }
        }
        .font(.system(size: 12)).foregroundStyle(ChatColor.secondary)
        .multilineTextAlignment(.center)
        .padding(.top, note == .waiting ? 12 : 10).padding(.bottom, note == .waiting ? 2 : 10)
        .frame(maxWidth: .infinity)
        .transition(.opacity)
    }
}

/// Before setup, or with a step left: Poki says so, and the bubble opens setup.
private struct SetupBubble: View {
    var paired: Bool
    var openSetup: () -> Void
    var body: some View {
        HStack {
            Button(action: openSetup) {
                HStack(spacing: 4) {
                    Text(paired ? "Finish setting up this iPhone." : "First, set up this iPhone. About 5 minutes.")
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                }
                .font(.system(size: 17)).foregroundStyle(Site.blue)
                .padding(.vertical, .messageVerticalPadding).padding(.horizontal, 14)
                .background(ChatColor.incoming, in: UnevenRoundedRectangle(topLeadingRadius: .cornerRadius, bottomLeadingRadius: .tailRadius,
                                                                            bottomTrailingRadius: .cornerRadius, topTrailingRadius: .cornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            Spacer(minLength: .messageInsetPadding)
        }
        .padding(.top, 4)
    }
}

// MARK: Chat and Voice

enum RootPage: Hashable { case chat, voice }

/// CHAT and VOICE under the page, like Photo and Video in Camera: the page's own word sits in the middle.
struct ModeLabels: View {
    var page: RootPage
    var dark: Bool
    var select: ((RootPage) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 22) {
                label("CHAT", .chat)
                label("VOICE", .voice)
            }
            // The board's 66 and 62 pt: the page's word in the middle.
            .padding(.leading, page == .chat ? 66 : 0).padding(.trailing, page == .voice ? 62 : 0)
            .padding(.top, 6).padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private func label(_ title: LocalizedStringKey, _ target: RootPage) -> some View {
        Button { select?(target) } label: {
            Text(title).font(.system(size: 13, weight: .semibold)).tracking(13 * 0.06)
                .foregroundStyle(color(target))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(page == target ? .isSelected : [])
    }

    private func color(_ target: RootPage) -> Color {
        if dark { return page == target ? .white : .white.opacity(0.55) }
        return page == target ? Site.blue : ChatColor.secondary
    }
}

// MARK: Composer

// ComposerInputView is from GetStream/swiftui-iMessage-clone (commit df114b4,
// iMessageClone/MessageList/View/Composer/ComposerInputView.swift, by Stefan Blos; no licence file in
// the repository), with the plus button in front from exyte/Chat (commit f382a14,
// Sources/ExyteChat/Views/InputView/InputView.swift, Copyright (c) 2019 exyte, MIT License). Changed: the
// board's sizes and greys, a microphone that opens Voice instead of the "not implemented" alert, a stop
// button while a task runs, and the plus button's menu.
struct ComposerInputView: View {
    var running: Bool
    var send: (String) -> Void
    var stop: () -> Void
    var openVoice: () -> Void
    var openModel: () -> Void
    var newConversation: () -> Void
    @State private var input = ""

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Menu {
                Button("New Conversation", systemImage: "square.and.pencil", action: newConversation)
                Button("Model", systemImage: "cpu", action: openModel)
            } label: {
                Image(systemName: "plus").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(.secondaryLabel))
                    .frame(width: 34, height: 34).background(ChatColor.incoming, in: .circle)
            }
            .padding(.bottom, 1)
            .accessibilityLabel(Text("More"))

            HStack(alignment: .bottom, spacing: 10) {
                TextField(text: $input, prompt: Text("Message Poki").foregroundStyle(ChatColor.placeholder), axis: .vertical) { Text("Message Poki") }
                    .font(.system(size: 17))
                    .multilineTextAlignment(.leading)
                    .lineLimit(1...5)
                    .padding(.vertical, 6.5)
                    .submitLabel(.send)
                    .onSubmit(submit)
                trailing.frame(height: 34)
            }
            .padding(.leading, 14).padding(.trailing, 6)
            .frame(minHeight: 36)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(ChatColor.fieldEdge, lineWidth: 1))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    @ViewBuilder private var trailing: some View {
        if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !running {
            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
                    .foregroundStyle(.white, Site.blue)
            }
            .accessibilityLabel(Text("Send"))
        } else if running {
            Button(action: stop) {
                Image(systemName: "stop.circle.fill").resizable().scaledToFit().frame(width: 26, height: 26).foregroundStyle(.white, Site.blue)
            }
            .accessibilityLabel(Text("Stop"))
        } else {
            Button(action: openVoice) {
                Image(systemName: "mic.fill").font(.system(size: 17)).foregroundStyle(ChatColor.secondary).frame(width: 24, height: 34)
            }
            .accessibilityLabel(Text("Voice"))
        }
    }

    private func submit() {
        guard !running else { return }
        send(input)
        input = ""
    }
}
