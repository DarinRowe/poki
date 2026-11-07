import PokiCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Memory: the routines agents saved on this iPhone (each repeats a task in one call) and
/// the owner's notes, both shared by Poki's own chat and every connected agent. Export and Import move
/// them between iPhones as one file; Poki Setup on the computer keeps the same file as a backup.
/// The maintainers' log bundle sits under Advanced, at the bottom.
struct MemoryView: View {
    var back: () -> Void
    @State private var routines: [Routine] = []
    @State private var notes: [MemoryNote] = []
    @State private var newNote = ""
    @State private var importing = false
    @State private var message: String?
    @State private var exportURL: URL?
    @State private var bundleURL: URL?
    @State private var advanced = false
    @State private var confirmClear = false
    private let store = RoutineStore.shared

    var body: some View {
        SitePage {
            VStack(spacing: 0) {
                Grabber()
                SheetHeader(title: Text("Memory"), back: "Settings", onBack: back)
                ScrollView {
                    VStack(spacing: 0) {
                        GroupLabel(text: "ROUTINES")
                        VStack(spacing: 0) {
                            if routines.isEmpty {
                                WhiteRow(title: "None yet", titleColor: Site.text3, divider: false)
                            }
                            ForEach(routines, id: \.name) { r in
                                RoutineRow(routine: r, divider: r.name != routines.last?.name)
                                    .contextMenu {
                                        Button("Forget", systemImage: "trash", role: .destructive) { _ = store.forget(r.name); reload() }
                                    }
                            }
                        }
                        .whiteCard()
                        GroupFootnote(text: "An agent saves a routine after a task that worked; the next time it repeats the task in one step and stops where the screen differs. Touch and hold a routine to forget it.")

                        GroupLabel(text: "NOTES")
                        VStack(spacing: 0) {
                            ForEach(notes, id: \.id) { n in
                                WhiteRow(title: LocalizedStringKey(n.text)) {
                                    Text(verbatim: n.by).site(13, line: 16).foregroundStyle(Site.text3)
                                }
                                .contextMenu {
                                    Button("Forget", systemImage: "trash", role: .destructive) { _ = store.forgetNote(n.id); reload() }
                                }
                            }
                            HStack {
                                TextField(text: $newNote, prompt: Text("e.g., Mom is “Mama” in Contacts").foregroundStyle(Site.text3)) { Text("Note") }
                                    .site(17, line: 22).foregroundStyle(Site.text)
                                    .submitLabel(.done).onSubmit(addNote)
                                Button(action: addNote) { Text("Add").site(17, line: 20).foregroundStyle(canAdd ? Site.ink : Site.text3) }
                                    .buttonStyle(.plain).disabled(!canAdd)
                            }
                            .padding(.vertical, 8).padding(.horizontal, 16)
                        }
                        .whiteCard()
                        GroupFootnote(text: "Every agent sees these notes before a task. They stay on this iPhone.")

                        GroupLabel(text: "MOVE OR BACK UP")
                        VStack(spacing: 0) {
                            if let exportURL {
                                ShareLink(item: exportURL) { WhiteRow(title: "Export Memory", titleColor: Site.ink) }
                                    .buttonStyle(.plain)
                            }
                            Button { importing = true } label: { WhiteRow(title: "Import Memory", titleColor: Site.ink, divider: false) }
                                .buttonStyle(.plain)
                        }
                        .whiteCard()
                        if let message {
                            GroupFootnote(text: LocalizedStringKey(message))
                        } else {
                            GroupFootnote(text: "One file with every routine and note. Importing merges it in; the newer copy of a routine wins. Poki Setup on your computer can back it up and put it back.")
                        }

                        Button { withAnimation { advanced.toggle() } } label: {
                            HStack(spacing: 4) {
                                Text("Advanced").site(13, line: 16)
                                Image(systemName: advanced ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(Site.c4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 28).padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                        if advanced {
                            VStack(spacing: 0) {
                                if let bundleURL {
                                    ShareLink(item: bundleURL) { WhiteRow(title: "Share Run Log for Maintainers", titleColor: Site.ink) }
                                        .buttonStyle(.plain)
                                }
                                Button { confirmClear = true } label: { WhiteRow(title: "Clear Memory", titleColor: Site.danger, divider: false) }
                                    .buttonStyle(.plain)
                            }
                            .whiteCard()
                            .padding(.top, 8)
                            GroupFootnote(text: "The run log lists each routine run, where it stopped and how long it took, with no typed text. It helps the Poki maintainers make routines more reliable.")
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 40)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: reload)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    message = try store.importData(data, by: "import")
                } catch {
                    message = String(localized: "That file could not be imported: \(String(describing: error))")
                }
                reload()
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .confirmationDialog("Clear all routines and notes on this iPhone?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear Memory", role: .destructive) { store.clearAll(); reload() }
        }
    }

    private var canAdd: Bool { !newNote.trimmingCharacters(in: .whitespaces).isEmpty }

    private func addNote() {
        guard canAdd else { return }
        _ = store.remember(newNote.trimmingCharacters(in: .whitespaces), by: "owner")
        newNote = ""
        reload()
    }

    /// Reads the store again and writes the two share files (the export and the log bundle) to tmp.
    private func reload() {
        routines = store.routines.sorted { $0.updated > $1.updated }
        notes = store.notes
        let tmp = FileManager.default.temporaryDirectory
        let export = tmp.appendingPathComponent(RoutineStore.backupName)
        if let data = try? store.exportData(), (try? data.write(to: export, options: .atomic)) != nil { exportURL = export }
        let bundle = tmp.appendingPathComponent("poki-agent-debug.json")
        if (try? store.debugBundle().write(to: bundle, options: .atomic)) != nil { bundleURL = bundle }
    }
}

/// A routine: its name, how many steps, how often it worked, and a flag when it stopped twice in a row.
private struct RoutineRow: View {
    var routine: Routine
    var divider: Bool
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: routine.name).site(17, line: 22).foregroundStyle(Site.text)
                Text(detail).site(13, line: 16).foregroundStyle(routine.stale ? Site.danger : Site.text3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let ms = routine.lastMs {
                Text(verbatim: String(format: "%.1f s", Double(ms) / 1000)).site(15, line: 18).foregroundStyle(Site.text3)
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 16)
        .overlay(alignment: .bottom) { if divider { Site.hair.frame(height: 1) } }
    }

    private var detail: String {
        let steps = String(localized: "\(routine.steps.count) steps")
        let runs = routine.runs == 0 ? String(localized: "not run yet") : String(localized: "worked \(routine.ok) of \(routine.runs)")
        let base = "\(steps) · \(runs) · \(routine.savedBy)"
        return routine.stale ? String(localized: "Needs redoing: stopped twice in a row") + " · " + base : base
    }
}
