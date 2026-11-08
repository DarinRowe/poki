import SwiftUI

/// Setup's Apple Account step: sign in once, so Poki can keep its own signing. Sections of the
/// step's Form, like the other steps.
struct AccountPage: View {
    @Environment(AppModel.self) private var model
    @State private var appleID = ""
    @State private var password = ""
    @State private var keepPassword = true
    @State private var code = ""

    private var signer: SelfSigner { model.signer }

    var body: some View {
        if signer.signedIn {
            Section {
                LabeledContent("Apple Account", value: signer.status?.apple_id ?? "")
                if let name = signer.status?.name, name != signer.status?.apple_id { LabeledContent("Name", value: name) }
                if signer.teams.count > 1 {
                    Picker("Team", selection: Binding(get: { signer.status?.team_id ?? "" }, set: { id in
                        if let team = signer.teams.first(where: { $0.team_id == id }) { Task { await signer.choose(team: team) } }
                    })) {
                        ForEach(signer.teams) { team in Text(team.is_free ? "\(team.name) (Free)" : team.name).tag(team.team_id) }
                    }
                } else if let team = signer.teams.first {
                    LabeledContent("Team", value: team.is_free ? "\(team.name) (Free, 7-day signing)" : team.name)
                }
            } footer: {
                Text(signer.status?.keeps_password == true
                     ? "Poki keeps the password in this iPhone’s Keychain to sign itself again every week."
                     : "Poki signs in again when its signing is due, and asks you for the password then.")
            }
            .task { if signer.teams.isEmpty { await signer.loadTeams() } }
            Section { Button("Sign Out", role: .destructive) { Task { await signer.signOut() } } }
        } else if signer.needsCode {
            Section {
                TextField("Verification Code", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                Button("Verify") { Task { await signer.finishSignIn(code: code); code = "" } }
                    .disabled(code.count != 6 || signer.working != nil)
            } footer: {
                Text("Apple sent a six-digit code to your trusted devices or phone number.")
            }
        } else {
            Section {
                TextField("Apple ID", text: $appleID)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textContentType(.password)
                Toggle("Keep Me Signed In", isOn: $keepPassword)
            } footer: {
                Text("A free Apple Account works: Poki signs itself for 7 days at a time and gets ready to sign again before then. Your Apple ID and password go only to Apple. The anisette server Poki asks for its device headers never sees them.")
            }
            Section {
                Button("Sign In") { Task { await signer.signIn(appleID: appleID, password: password, keepPassword: keepPassword); password = "" } }
                    .disabled(appleID.isEmpty || password.isEmpty || signer.working != nil)
            }
        }
        SignerActivityRows(signer: signer)
    }
}

/// What the signer is doing, or why it stopped.
struct SignerActivityRows: View {
    let signer: SelfSigner
    var body: some View {
        if let working = signer.working {
            Section {
                if let f = signer.fraction { ProgressView(value: f) { Text(working) } } else { LabeledContent { ProgressView() } label: { Text(working) } }
            }
        }
        if let error = signer.lastError {
            Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
        }
    }
}

/// The Setup page's signing section: when Poki stops opening, the build that is ready, and Install.
struct SigningSection: View {
    @Environment(AppModel.self) private var model
    private var signer: SelfSigner { model.signer }

    var body: some View {
        Section {
            LabeledContent("Signed Until") {
                if let expiry = signer.expiry {
                    VStack(alignment: .trailing) {
                        Text(expiry, format: .dateTime.month().day().hour().minute())
                        Text(expiry, style: .relative).font(.footnote).foregroundStyle(countdownColor)
                    }
                } else {
                    Text("No Profile").foregroundStyle(.secondary)
                }
            }
            if let next = signer.next {
                LabeledContent(next.kind == "update" ? "Update Ready" : "Refresh Ready") {
                    VStack(alignment: .trailing) {
                        Text(next.kind == "update" ? "\(next.version) (\(next.build))" : "Until \(next.expires.formatted(date: .abbreviated, time: .omitted))")
                        Text(next.team_name).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Button(next.kind == "update" ? "Install Update" : "Install Refresh", systemImage: "arrow.down.app") { Task { await signer.install() } }
                    .disabled(!model.signingIdle || signer.working != nil)
            } else if let latest = signer.latest, signer.isNewer(latest) {
                LabeledContent("Update Available", value: "\(latest.version) (\(latest.build))")
            }
            Button("Prepare Refresh Now", systemImage: "arrow.clockwise") { Task { await signer.prepare(kind: "refresh") } }
                .disabled(!signer.signedIn || signer.working != nil)
            NavigationLink { SigningOptionsPage() } label: { LabeledContent("Release Channel", value: signer.channelTitle) }
        } header: {
            Text("Signing")
        } footer: {
            Text(footer)
        }
        SignerActivityRows(signer: signer)
    }

    private var countdownColor: Color {
        guard let days = signer.daysLeft else { return .secondary }
        return days <= 1 ? .red : days <= SelfSigner.refreshWithDaysLeft ? .orange : .secondary
    }

    private var footer: String {
        if !signer.signedIn { return String(localized: "Sign in to your Apple Account in Setup so Poki can sign itself again before it expires.") }
        if signer.next != nil {
            return model.signingIdle
                ? String(localized: "Installing closes Poki for a moment. Your chats and setup stay.")
                : String(localized: "Install is available when Poki isn’t running a task.")
        }
        return String(localized: "Poki gets the next build ready by itself, \(Int(SelfSigner.refreshWithDaysLeft)) days before it expires or when your channel has an update. It installs only when you tap Install.")
    }
}

/// The release channel and the anisette server.
struct SigningOptionsPage: View {
    @Environment(AppModel.self) private var model
    @State private var anisette = ""
    private var signer: SelfSigner { model.signer }

    /// Shown most stable first, as the person reads them.
    private var channels: [SelfSigner.Channel] {
        let order = ["stable", "beta", "alpha", "pre-alpha"]
        return (signer.status?.channels ?? []).sorted { (order.firstIndex(of: $0.id) ?? 9) < (order.firstIndex(of: $1.id) ?? 9) }
    }

    var body: some View {
        Form {
            Section {
                Picker("Release Channel", selection: Binding(get: { signer.status?.channel ?? "stable" }, set: { id in Task { await signer.setChannel(id) } })) {
                    ForEach(channels) { Text($0.title).tag($0.id) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Release Channel")
            } footer: {
                Text("Poki downloads and signs updates from this channel ahead of time, the same way Poki Setup does. Stable gets full releases only; Beta, Alpha and Pre-alpha get earlier builds.")
            }
            Section {
                TextField("https://new.ani.sidestore.io", text: $anisette)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await signer.setAnisette(anisette) } }
                Button("Use Default Server") { anisette = ""; Task { await signer.setAnisette("") } }
            } header: {
                Text("Anisette Server")
            } footer: {
                Text("Apple’s sign-in needs device headers that only Apple hardware makes. Poki gets them from this anisette server. It never sees your Apple ID or password.")
            }
            SignerActivityRows(signer: signer)
        }
        .navigationTitle("Signing")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { anisette = signer.status?.anisette ?? "" }
    }
}
