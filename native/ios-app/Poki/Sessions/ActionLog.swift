import SwiftUI

/// Every action Poki ran on this iPhone, for the owner's own record: append-only, kept on this device,
/// with no way to delete it from the app. Each entry names the session it came from (Poki's chat or an
/// outside agent's), so a tap opens that run.
@MainActor
@Observable
final class ActionLog {
    static let shared = ActionLog()

    struct Entry: Codable, Identifiable, Hashable {
        var id = UUID()
        var at: Date
        var text: String
        var app: String?
        var ok: Bool
        var session: String?
        /// The outside agent that asked for it; nil for Poki's own chat.
        var caller: String? = nil
    }

    private(set) var entries: [Entry] = []
    private let file: URL
    private var loaded = false

    private init() {
        let folder = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        file = folder.appendingPathComponent("action-log.jsonl")
    }

    func add(_ text: String, app: String?, ok: Bool, session: String?, caller: String? = nil) {
        load()
        let entry = Entry(at: Date(), text: text, app: app, ok: ok, session: session, caller: caller)
        entries.append(entry)
        guard var line = try? JSONEncoder().encode(entry) else { return }
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: file, options: .atomic)
        }
    }

    func load() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: file) else { return }
        entries = data.split(separator: 0x0A).compactMap { try? JSONDecoder().decode(Entry.self, from: Data($0)) }
    }
}

/// Poki › Activity Log: every action, newest first, grouped by day. A tap opens the run it came from.
struct ActionLogView: View {
    var openSession: (String) -> Void
    private var log: ActionLog { ActionLog.shared }

    var body: some View {
        let days = Dictionary(grouping: log.entries.reversed(), by: { Calendar.current.startOfDay(for: $0.at) }).sorted { $0.key > $1.key }
        List {
            if log.entries.isEmpty {
                ContentUnavailableView("No Actions Yet", systemImage: "list.bullet.rectangle",
                                       description: Text("Every tap, swipe and keystroke Poki makes on this iPhone is listed here, whoever asked for it."))
                    .listRowBackground(Color.clear)
            }
            ForEach(days, id: \.key) { day, entries in
                Section(day.formatted(date: .complete, time: .omitted)) {
                    ForEach(entries) { entry in
                        Button { if let id = entry.session { openSession(id) } } label: { row(entry) }
                            .disabled(entry.session.flatMap { SessionStore.shared.session($0) } == nil)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Activity Log")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { log.load() }
    }

    private func row(_ entry: ActionLog.Entry) -> some View {
        HStack(alignment: .center, spacing: 10) {
            // Who asked for it: the agent's badge, or Poki's own.
            Group {
                if let caller = entry.caller { CallerBadge(name: caller, size: 28) } else { PokiAvatar(size: 28) }
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: entry.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(entry.ok ? Color.green : Color.red)
                    .background(Circle().fill(Color(.systemBackground)).padding(-1))
                    .offset(x: 3, y: 3)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(ActivityWords.label(entry.text)).foregroundStyle(Color(.label)).lineLimit(2)
                Text([entry.app, entry.session.flatMap { SessionStore.shared.session($0)?.name }].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(entry.at, style: .time).font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}
