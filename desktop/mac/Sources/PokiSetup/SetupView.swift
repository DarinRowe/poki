import SwiftUI
import UniformTypeIdentifiers

struct SetupView: View {
    @EnvironmentObject var model: AppModel
    @State private var ipa: URL?
    @State private var choosingIPA = false
    @State private var handOff = false
    @State private var result: InstallAnswer?
    @State private var failed: String?

    private var installing: Bool { model.busyJobs.contains("install") }

    var body: some View {
        Form {
            phoneSection
            accountSection
            appSection
            if let steps = model.steps["install"], !steps.isEmpty {
                Section("Progress") { StepsView(steps: steps) }
            }
            if let result { resultSection(result) }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $choosingIPA, allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data]) { r in
            if case .success(let url) = r { ipa = url }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await install() }
                } label: {
                    Label("Install Poki", systemImage: "arrow.down.app")
                }
                .disabled(!canInstall)
                .help("Sign Poki with your Apple Account and install it on the iPhone")
            }
        }
    }

    // MARK: iPhone

    @ViewBuilder private var phoneSection: some View {
        Section {
            if let err = model.phonesError {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Poki Setup can't see iPhones right now")
                        Text(err.message).font(.callout).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "cable.connector.slash").foregroundStyle(.orange)
                }
            } else if model.phones.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "cable.connector")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(Color.pokiBlue)
                        .frame(width: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Connect your iPhone").font(.headline)
                        Text("Use a cable, unlock the iPhone and tap Trust when it asks.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ProgressView().controlSize(.small)
                }
                .padding(.vertical, 4)
            } else {
                if model.phones.count > 1 {
                    Picker("iPhone", selection: Binding(get: { model.selectedPhone?.id ?? "" }, set: { model.selectedUDID = $0 })) {
                        ForEach(model.phones) { Text($0.title).tag($0.id) }
                    }
                }
                if let row = model.selectedPhone { phoneRows(row) }
            }
        } header: {
            Text("iPhone")
        }
    }

    @ViewBuilder private func phoneRows(_ row: PhoneRow) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Color.pokiBlue)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.headline)
                if let f = row.facts {
                    Text("iOS \(f.ios) · \(f.productType)").font(.callout).foregroundStyle(.secondary)
                } else if let e = row.error {
                    Text(e).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        if let f = row.facts {
            LabeledContent("Trusts This Mac") {
                if f.pairedWithThisComputer {
                    statusText("Yes", .green)
                } else {
                    Button("Pair") { Task { await run { try await model.pair(udid: f.udid) } } }
                        .disabled(model.busyJobs.contains("pair"))
                }
            }
            LabeledContent("Developer Mode") {
                switch f.developerMode {
                case .some(true): statusText("On", .green)
                case .some(false):
                    Button("Turn On…") { Task { await run { try await model.enableDeveloperMode(udid: f.udid) } } }
                        .disabled(model.busyJobs.contains("devmode"))
                case .none: Text("Checked during setup").foregroundStyle(.secondary)
                }
            }
            if let s = model.steps["devmode"], !s.isEmpty, model.busyJobs.contains("devmode") { StepsView(steps: s) }
            if let s = model.steps["pair"], !s.isEmpty, model.busyJobs.contains("pair") { StepsView(steps: s) }
            if let r = row.record {
                LabeledContent("Poki") {
                    statusText("\(r.version) · \(relativeDays(r))", r.daysLeft <= 2 ? .orange : .green)
                }
            }
        }
    }

    private func statusText(_ s: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(s).foregroundStyle(.secondary)
        }
    }

    // MARK: Account

    @ViewBuilder private var accountSection: some View {
        Section("Apple Account") {
            if let a = model.account, a.signedIn {
                LabeledContent("Signed In As") { Text(a.name ?? a.appleId ?? "").foregroundStyle(.secondary) }
                if model.teams.count > 1 {
                    Picker("Team", selection: Binding(get: { a.teamId ?? model.teams.first?.teamId ?? "" }, set: { id in
                        if let t = model.teams.first(where: { $0.teamId == id }) { Task { await model.chooseTeam(t) } }
                    })) {
                        ForEach(model.teams) { t in Text(t.isFree ? "\(t.name) (free)" : t.name).tag(t.teamId) }
                    }
                } else if let t = model.teams.first {
                    LabeledContent("Team") { Text(t.isFree ? "\(t.name), free (7-day apps)" : t.name).foregroundStyle(.secondary) }
                }
            } else {
                LabeledContent("Sign in with the Apple Account Poki is signed for") {
                    Button("Sign In…") { model.page = .account }
                }
            }
        }
    }

    // MARK: App

    @ViewBuilder private var appSection: some View {
        Section {
            LabeledContent("Poki Build") {
                HStack {
                    if let ipa {
                        Text(ipa.lastPathComponent).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Button { self.ipa = nil } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary)
                            .accessibilityLabel("Use the latest release instead")
                    } else if let latest = model.latest {
                        Text("Latest release, \(latest.version)").foregroundStyle(.secondary)
                    } else {
                        Text("Choose a Poki IPA").foregroundStyle(.secondary)
                    }
                    Button("Choose…") { choosingIPA = true }
                }
            }
            Toggle("Also show a QR code to send the pairing file over Wi-Fi", isOn: $handOff)
            HStack {
                Spacer()
                Button {
                    Task { await install() }
                } label: {
                    Text(installing ? "Installing…" : "Install Poki").frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!canInstall)
            }
            if let failed {
                Text(failed).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
        } header: {
            Text("Poki")
        } footer: {
            Text(footer).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var footer: String {
        if model.account?.signedIn != true { return "Sign in first. Your Apple Account password goes to Apple only." }
        if ipa == nil && model.latest == nil { return "No Poki release is published yet. Choose the Poki IPA you downloaded (the “external” one)." }
        return "Poki Setup signs Poki for your team, installs it, and gives Poki its pairing file, so it can work on its own."
    }

    private var canInstall: Bool {
        !installing && model.selectedPhone?.facts != nil && model.account?.signedIn == true && (ipa != nil || model.latest != nil)
    }

    @ViewBuilder private func resultSection(_ r: InstallAnswer) -> some View {
        Section("Done") {
            Label("Poki \(r.record.version) is on \(r.record.phoneName). It stays signed until \(r.record.expires.formatted(date: .abbreviated, time: .shortened)).", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.primary)
            ForEach(Array(r.notes.enumerated()), id: \.offset) { _, n in
                Text(n).font(.callout).foregroundStyle(.secondary)
            }
            Text("On the iPhone: open Settings › General › VPN & Device Management, trust your Apple Account, then open Poki.")
                .font(.callout)
            if let h = r.handoff {
                HStack(alignment: .top, spacing: 16) {
                    QRCode(text: h.link, size: 150)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Scan with the iPhone's Camera").font(.headline)
                        Text("Keep the iPhone on the same Wi-Fi as this Mac. Poki opens and saves its pairing file.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Copy Link") { copyToPasteboard(h.link) }
                    }
                }
            }
        }
    }

    private func install() async {
        guard let phone = model.selectedPhone else { return }
        failed = nil
        result = nil
        do {
            result = try await model.install(udid: phone.id, ipa: ipa, handOff: handOff)
        } catch {
            failed = error.localizedDescription
        }
    }

    private func run(_ body: () async throws -> Void) async {
        do { try await body() } catch { model.report(error) }
    }
}
