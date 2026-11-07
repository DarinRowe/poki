import AppKit
import SwiftUI

// MARK: Relay

struct RelayView: View {
    @EnvironmentObject var model: AppModel
    @State private var token = ""
    @State private var accounts: [CloudflareAccount] = []
    @State private var accountID = ""
    @State private var working = false
    @State private var error: String?
    @State private var relayUp: Bool?

    var body: some View {
        Form {
            Section {
                Text("Poki's relay lets AI apps reach your iPhone from anywhere. It is a small Cloudflare Worker in your own Cloudflare account. It passes messages along and stores nothing. The free plan is enough.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let d = model.relay {
                Section("Your Relay") {
                    LabeledContent("Address") { Text(d.address).foregroundStyle(.secondary).textSelection(.enabled) }
                    LabeledContent("Cloudflare Account") { Text(d.accountName).foregroundStyle(.secondary) }
                    LabeledContent("Status") {
                        HStack(spacing: 8) {
                            switch relayUp {
                            case .some(true): Label("Answering", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            case .some(false): Label("Not answering", systemImage: "xmark.circle.fill").foregroundStyle(.red)
                            case .none: EmptyView()
                            }
                            Button("Check") { Task { await check(d.address) } }
                        }
                    }
                    HStack(alignment: .top, spacing: 16) {
                        QRCode(text: d.phoneLink, size: 130)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Give the address to Poki").font(.headline)
                            Text("Scan this with the iPhone's Camera. Poki opens and starts using this relay.")
                                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Button("Copy Link") { copyToPasteboard(d.phoneLink) }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Section {
                SecureField("Cloudflare API Token", text: $token)
                if !accounts.isEmpty {
                    Picker("Account", selection: $accountID) {
                        ForEach(accounts) { Text($0.name).tag($0.id) }
                    }
                }
                if let s = model.steps["relay"], !s.isEmpty { StepsView(steps: s) }
                HStack {
                    Link("Create a token…", destination: URL(string: "https://dash.cloudflare.com/profile/api-tokens")!)
                    Spacer()
                    if working { ProgressView().controlSize(.small) }
                    if accounts.isEmpty {
                        Button("Continue") { Task { await loadAccounts() } }.disabled(token.isEmpty || working)
                    } else {
                        Button(model.relay == nil ? "Deploy Relay" : "Update Relay") { Task { await deploy() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(accountID.isEmpty || working)
                    }
                }
                if let error { Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled) }
            } header: {
                Text(model.relay == nil ? "Deploy" : "Redeploy")
            } footer: {
                Text("Use the “Edit Cloudflare Workers” template. Poki Setup uses the token once and doesn't keep it.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { if let d = model.relay, !model.demo { await check(d.address) } else if model.demo { relayUp = true } }
    }

    private func loadAccounts() async {
        working = true
        error = nil
        defer { working = false }
        do {
            accounts = try await model.bridge.call("relay_accounts", ["token": token])
            accountID = accounts.first?.id ?? ""
            if accounts.isEmpty { error = "This token can't see any Cloudflare account." }
        } catch { self.error = error.localizedDescription }
    }

    private func deploy() async {
        working = true
        error = nil
        defer { working = false }
        do {
            let d: Deployed = try await model.job("relay") { try await model.bridge.call("relay_deploy", ["token": token, "account_id": accountID]) }
            model.relay = d
            token = ""
            accounts = []
            await check(d.address)
        } catch { self.error = error.localizedDescription }
    }

    private func check(_ address: String) async {
        relayUp = try? await model.bridge.call("relay_check", ["address": address])
    }
}

// MARK: Connectors

struct ConnectorsView: View {
    @EnvironmentObject var model: AppModel
    @State private var name = ""
    @State private var url = ""
    @State private var error: String?
    @State private var checking: Set<String> = []
    @State private var snippets: [String: [Snippet]] = [:]

    var body: some View {
        Form {
            Section {
                Text("A connector link lets an AI app such as Claude or ChatGPT use your iPhone. Poki makes the link on the iPhone (Poki › Connect). Keep it here to check that it works and to get the setup steps for each app.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(model.connectors) { c in connectorSection(c) }
            Section("Add a Link") {
                TextField("Name", text: $name, prompt: Text("Jane's iPhone"))
                TextField("Link", text: $url, prompt: Text("https://…/mcp"))
                HStack {
                    if let error { Text(error).foregroundStyle(.red).font(.callout) }
                    Spacer()
                    Button("Add") { Task { await add() } }.disabled(url.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private func connectorSection(_ c: Connector) -> some View {
        Section {
            LabeledContent(c.name) {
                HStack(spacing: 8) {
                    if checking.contains(c.url) {
                        ProgressView().controlSize(.small)
                    } else if let k = c.lastCheck {
                        Label(k.ok ? "Works" : (k.phoneOnline ? "Problem" : "iPhone offline"), systemImage: k.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(k.ok ? .green : .orange)
                    }
                    Button("Check") { Task { await check(c) } }.disabled(checking.contains(c.url))
                }
            }
            if let k = c.lastCheck {
                Text(k.ok ? "\(k.tools.count) tools: \(k.tools.prefix(8).joined(separator: ", "))" : k.detail)
                    .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            DisclosureGroup("Set up in an AI app") {
                ForEach(snippets[c.url] ?? []) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(s.name).font(.subheadline.weight(.semibold))
                            Spacer()
                            Button("Copy") { copyToPasteboard(s.text) }.buttonStyle(.borderless)
                        }
                        Text(s.text)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(.vertical, 2)
                }
            }
            .task { if snippets[c.url] == nil, !model.demo { snippets[c.url] = try? await model.bridge.call("connector_snippets", ["url": c.url]) } }
            HStack {
                Button("Copy Link") { copyToPasteboard(c.url) }
                Spacer()
                Button("Remove", role: .destructive) { Task { await forget(c) } }
            }
        }
    }

    private func add() async {
        error = nil
        do {
            let _: Connector = try await model.bridge.call("connector_add", ["name": name.isEmpty ? "iPhone" : name, "url": url.trimmingCharacters(in: .whitespacesAndNewlines)])
            name = ""
            url = ""
            model.connectors = try await model.bridge.call("connectors")
        } catch { self.error = error.localizedDescription }
    }

    private func check(_ c: Connector) async {
        checking.insert(c.url)
        defer { checking.remove(c.url) }
        do {
            let _: Check = try await model.bridge.call("connector_check", ["url": c.url])
            model.connectors = try await model.bridge.call("connectors")
        } catch { model.report(error) }
    }

    private func forget(_ c: Connector) async {
        do {
            try await model.bridge.run("connector_forget", ["url": c.url])
            model.connectors = try await model.bridge.call("connectors")
        } catch { model.report(error) }
    }
}

// MARK: Diagnostics

struct DiagnosticsView: View {
    @EnvironmentObject var model: AppModel
    @State private var filter = ""
    @State private var streaming = false
    @State private var showHelperLog = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("iPhone Log") {
                    HStack {
                        TextField("Filter", text: $filter, prompt: Text("Poki"))
                            .frame(maxWidth: 220)
                        Spacer()
                        Button(streaming ? "Stop" : "Start") { Task { await toggle() } }
                            .disabled(model.selectedPhone == nil && !streaming)
                        Button("Clear") { model.logLines.removeAll() }
                        Button("Copy") { copyToPasteboard(model.logLines.joined(separator: "\n")) }
                    }
                }
                Section("Tools") {
                    LabeledContent("Developer Disk Image") {
                        Button("Mount") { Task { await mount() } }.disabled(model.selectedPhone == nil)
                    }
                    LabeledContent("Support Bundle") {
                        Button("Save…") { Task { await saveBundle() } }
                    }
                    LabeledContent("Helper Log") {
                        Button(showHelperLog ? "Hide" : "Show") { showHelperLog.toggle() }
                    }
                    if let message { Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                }
            }
            .formStyle(.grouped)
            .frame(height: 250)
            ScrollViewReader { proxy in
                ScrollView {
                    let lines = showHelperLog ? model.bridge.helperLog : model.logLines
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(lines.suffix(2000).enumerated()), id: \.offset) { i, l in
                            Text(l).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).id(i)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: model.logLines.count) { _, _ in proxy.scrollTo(min(model.logLines.count, 2000) - 1, anchor: .bottom) }
            }
        }
    }

    private func toggle() async {
        do {
            if streaming {
                try await model.bridge.run("logs_stop")
                streaming = false
            } else if let p = model.selectedPhone {
                try await model.bridge.run("logs_start", ["udid": p.id, "filter": filter.isEmpty ? nil : filter])
                streaming = true
            }
        } catch { model.report(error) }
    }

    private func mount() async {
        guard let p = model.selectedPhone else { return }
        do {
            try await model.job("ddi") { try await model.bridge.run("mount_ddi", ["udid": p.id]) }
            message = "The Developer Disk Image is mounted."
        } catch { model.report(error) }
    }

    private func saveBundle() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Save Here"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        do {
            let path: String = try await model.bridge.call("support_bundle", ["udid": model.selectedPhone?.id, "out_dir": dir.path])
            message = "Saved \(path). It has no passwords or tokens."
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } catch { model.report(error) }
    }
}

// MARK: Settings

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var choice = ""
    @State private var custom = ""
    @State private var update: UpdateInfo?
    @State private var message: String?

    private let customTag = "custom"
    private let systemTag = "system"

    var body: some View {
        Form {
            Section {
                Picker("Identity Server", selection: $choice) {
                    ForEach(model.info?.anisetteServers ?? [], id: \.self) { u in
                        Text(URL(string: u)?.host ?? u).tag(u)
                    }
                    if model.info?.canUseSystemAnisette == true { Text("This Mac (macOS 26 and earlier)").tag(systemTag) }
                    Text("Other…").tag(customTag)
                }
                if choice == customTag {
                    TextField("Server Address", text: $custom, prompt: Text("https://"))
                }
                HStack {
                    if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Apply") { Task { await apply() } }
                }
            } header: {
                Text("Sign-In")
            } footer: {
                Text("Apple's sign-in wants proof that it talks to a Mac or PC (“anisette”). A server provides it; it never sees your Apple Account or password. If sign-in fails, try another one.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Updates") {
                LabeledContent("Version") { Text(model.info?.version ?? "").foregroundStyle(.secondary) }
                HStack {
                    if let u = update {
                        if u.newer, let s = u.url, let url = URL(string: s) {
                            Link("Poki Setup \(u.latest ?? "") is available", destination: url)
                        } else {
                            Text("Poki Setup is up to date.").foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Check for Updates") { Task { update = try? await model.bridge.call("check_update") } }
                }
            }
            Section("Data") {
                LabeledContent("Folder") {
                    Button("Show in Finder") {
                        if let d = model.info?.dataDir { NSWorkspace.shared.open(URL(fileURLWithPath: d)) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 460)
        .onAppear(perform: load)
    }

    private func load() {
        guard let src = model.account?.anisette else { choice = model.info?.defaultAnisette ?? ""; return }
        if src.kind == "system" {
            choice = systemTag
        } else if let u = src.url, (model.info?.anisetteServers ?? []).contains(u) {
            choice = u
        } else {
            choice = customTag
            custom = src.url ?? ""
        }
    }

    private func apply() async {
        let src: AnisetteSource = choice == systemTag ? .system : .remote(choice == customTag ? custom : choice)
        do {
            try await model.setAnisette(src)
            message = "Saved."
        } catch { message = error.localizedDescription }
    }
}
