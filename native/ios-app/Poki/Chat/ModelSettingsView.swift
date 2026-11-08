// The model page combines two files from lhuanyu/OllamaMessage (commit c857a02), Copyright (c) 2023
// Huanyu Luo, MIT License; see THIRD_PARTY_NOTICES.md:
// - OllamaMessage/Class/View/MessageList/DialogueSettingsView.swift: the "Model" row with its label and a hidden-label
//   Picker on the right;
// - OllamaMessage/Class/View/DialogueList/OllamaModelSelectionView.swift: one row per provider with its 30 pt icon, the
//   whole row tappable, and the footer under the list.
// Changed: the ESP-171 board "M Model" (the grouped rows, the provider tiles, "Add Key"), keys entered
// into the keychain instead of a server's model list, and the agents on a computer below.
import SwiftUI

/// Accounts, as the Mail app lists mail accounts: every model account on this iPhone whatever its
/// provider, each with what it is used for (the text chat, live voice) switched on or off inside it.
/// What an account can power is worked out from its type: any wired provider can run the text chat;
/// live voice needs OpenAI's Realtime API, so only an OpenAI API key can run it.
struct ModelSettingsView: View {
    var openAgents: () -> Void
    @State private var adding = false
    @State private var version = ModelKeys.saved

    var body: some View {
        List {
            Section {
                ForEach(ModelProvider.allCases.filter(ModelAccounts.isSetUp)) { provider in
                    NavigationLink { AccountDetail(provider: provider) } label: { AccountRow(provider: provider) }
                }
                Button("Add Account", systemImage: "plus") { adding = true }
            } header: {
                Text("Accounts")
            } footer: {
                Text("Keys and sign-ins stay in this iPhone’s Keychain. Poki sends each one only to its own provider.")
            }

            Section {
                LabeledContent("Text Chat", value: ModelKeys.hasUsableKey ? "\(ModelKeys.selectedProvider.name), \(ModelKeys.selectedModelName)" : String(localized: "No Account"))
                LabeledContent("Live Voice", value: VoiceDirect.apiKey != nil ? String(localized: "OpenAI") : String(localized: "No Account"))
                LabeledContent("Dictation", value: String(localized: "On This iPhone"))
            } header: {
                Text("In Use")
            } footer: {
                Text("Open an account to choose what it is used for. Dictation in the message field needs no account.")
            }

            Section {
                Button(action: openAgents) { Label("Claude Code or Codex on a Computer", systemImage: "terminal") }
            } footer: {
                Text("Agents you already run can drive Poki over its MCP address; your computer does the thinking and Poki only taps and types.")
            }
        }
        .id(version)
        .listStyle(.insetGrouped)
        .navigationTitle("Accounts")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: ModelKeys.changed)) { _ in version = ModelKeys.saved }
        .sheet(isPresented: $adding) { AddAccount() }
    }
}

/// What a model account is and what it can power.
enum ModelAccounts {
    static func isSetUp(_ provider: ModelProvider) -> Bool {
        switch provider {
        case .custom: !ModelKeys.customURL.isEmpty
        case .chatgpt: ChatGPTAccount.signedIn
        default: ModelKeys.hasKey(provider)
        }
    }

    static func canChat(_ provider: ModelProvider) -> Bool { provider.wired }
    /// Live voice is OpenAI's Realtime API: an OpenAI API key only (a ChatGPT sign-in can't open it).
    static func canTalkLive(_ provider: ModelProvider) -> Bool { provider == .openai }

    static func method(_ provider: ModelProvider) -> String {
        switch provider {
        case .chatgpt: String(localized: "Sign in with ChatGPT")
        case .custom: String(localized: "OpenAI-compatible address")
        default: String(localized: "API key")
        }
    }

    /// "Text Chat, Live Voice", "Not in use".
    static func uses(_ provider: ModelProvider) -> String {
        var out: [String] = []
        if ModelKeys.selectedProvider == provider, ModelKeys.hasUsableKey { out.append(String(localized: "Text Chat")) }
        if canTalkLive(provider), VoiceDirect.apiKey != nil { out.append(String(localized: "Live Voice")) }
        return out.isEmpty ? String(localized: "Not in use") : out.joined(separator: ", ")
    }
}

private struct AccountRow: View {
    var provider: ModelProvider
    var body: some View {
        HStack(spacing: 12) {
            ProviderTile(provider: provider)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: provider.name)
                Text(ModelAccounts.uses(provider)).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// One account: its type and connection, what it is used for (switches; the ones it can't power are
/// shown greyed with why), its model, and Delete.
private struct AccountDetail: View {
    @Environment(\.dismiss) private var dismiss
    var provider: ModelProvider
    @State private var editing = false
    @State private var signingIn = false
    @State private var version = ModelKeys.saved
    @State private var model = ""

    var body: some View {
        Form {
            Section {
                LabeledContent("Type", value: provider.name)
                LabeledContent("Connection", value: ModelAccounts.method(provider))
                if provider == .custom { LabeledContent("Address", value: ModelKeys.customURL) }
                Button(provider.signsIn ? "Sign In Again" : provider == .custom ? "Edit Address and Key" : "Replace Key") {
                    if provider.signsIn { signingIn = true } else { editing = true }
                }
            }

            Section {
                Toggle(isOn: Binding(get: { ModelKeys.selectedProvider == provider }, set: { on in
                    if on { ModelKeys.selectedProvider = provider }
                    else if let other = ModelProvider.allCases.first(where: { $0 != provider && ModelAccounts.isSetUp($0) && ModelAccounts.canChat($0) }) {
                        ModelKeys.selectedProvider = other
                    }
                    version = ModelKeys.saved
                })) {
                    Label("Text Chat", systemImage: "bubble.left.and.text.bubble.right")
                }
                .disabled(!ModelAccounts.canChat(provider))
                if ModelKeys.selectedProvider == provider, provider.models.count > 1 {
                    Picker("Model", selection: $model) {
                        ForEach(provider.models) { Text($0.name).tag($0.id) }
                    }
                    .onChange(of: model) { _, new in if !new.isEmpty { ModelKeys.selectedModel = new } }
                }
                Toggle(isOn: Binding(get: { ModelAccounts.canTalkLive(provider) && VoiceDirect.enabled }, set: { VoiceDirect.enabled = $0; version += 1 })) {
                    Label("Live Voice", systemImage: "waveform")
                }
                .disabled(!ModelAccounts.canTalkLive(provider))
            } header: {
                Text("Use This Account For")
            } footer: {
                if !ModelAccounts.canChat(provider) {
                    Text("Poki keeps this key; chatting with \(provider.name) comes in an update.")
                } else if !ModelAccounts.canTalkLive(provider) {
                    Text("Live voice runs on OpenAI’s Realtime API, which only an OpenAI API key can open. Dictation in the message field works with this account.")
                } else {
                    Text("Only one account runs the text chat at a time.")
                }
            }

            Section {
                Button(provider.signsIn ? "Sign Out" : "Delete Account", role: .destructive) {
                    if provider == .custom { ModelKeys.customURL = ""; ModelKeys.customModel = "" }
                    ModelKeys.remove(provider)
                    if ModelKeys.selectedProvider == provider, let other = ModelProvider.allCases.first(where: { ModelAccounts.isSetUp($0) && ModelAccounts.canChat($0) }) {
                        ModelKeys.selectedProvider = other
                    }
                    dismiss()
                }
            }
        }
        .id(version)
        .navigationTitle(Text(verbatim: provider.name))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model = ModelKeys.model(for: provider) }
        .sheet(isPresented: $editing, onDismiss: { version = ModelKeys.saved }) { KeyEntry(provider: provider) }
        .sheet(isPresented: $signingIn, onDismiss: { version = ModelKeys.saved }) { ChatGPTSignIn() }
    }
}

/// Add Account: the account types, each with how it connects; choosing one opens its key, address or
/// sign-in.
private struct AddAccount: View {
    @Environment(\.dismiss) private var dismiss
    @State private var editing: ModelProvider?
    @State private var signingIn = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ModelProvider.allCases) { provider in
                        Button { if provider.signsIn { signingIn = true } else { editing = provider } } label: {
                            HStack(spacing: 12) {
                                ProviderTile(provider: provider)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: provider.name).foregroundStyle(Color(.label))
                                    Text(capabilities(provider)).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if ModelAccounts.isSetUp(provider) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                    }
                } footer: {
                    Text("Text chat works with every account. Live voice needs an OpenAI API key.")
                }
            }
            .navigationTitle("Add Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(item: $editing, onDismiss: { if editing == nil { dismiss() } }) { provider in KeyEntry(provider: provider) }
            .sheet(isPresented: $signingIn, onDismiss: { if ChatGPTAccount.signedIn { dismiss() } }) { ChatGPTSignIn() }
        }
    }

    private func capabilities(_ provider: ModelProvider) -> String {
        let how = ModelAccounts.method(provider)
        if ModelAccounts.canTalkLive(provider) { return String(localized: "\(how) · Text chat and live voice") }
        if ModelAccounts.canChat(provider) { return String(localized: "\(how) · Text chat") }
        return String(localized: "\(how) · Coming in an update")
    }
}

/// Entering, replacing or removing one provider's key. The field is secure and the key is never shown
/// again after it is saved.
private struct KeyEntry: View {
    @Environment(\.dismiss) private var dismiss
    var provider: ModelProvider
    @State private var key = ""
    @State private var url = ModelKeys.customURL
    @State private var modelID = ModelKeys.customModel
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Form {
                if provider == .custom {
                    Section {
                        TextField("https://…/v1", text: $url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Model, such as llama-4-maverick", text: $modelID).textInputAutocapitalization(.never).autocorrectionDisabled()
                    } header: { Text("Address and model") }
                }
                Section {
                    SecureField(provider.keyPrompt, text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: {
                    Text("\(provider.name) key")
                } footer: {
                    if !provider.wired {
                        Text("Poki keeps the key now; chatting with \(provider.name) comes in an update. Until then, choose Anthropic or OpenAI.")
                    } else if ModelKeys.hasKey(provider) {
                        Text("A key is saved. Enter a new one to replace it.")
                    } else {
                        Text(verbatim: provider.keyHelp)
                    }
                }
                if failed { Text("The keychain did not take the key. Try again.").foregroundStyle(Color(.systemRed)) }
                if ModelKeys.hasKey(provider) {
                    Section { Button("Remove Key", role: .destructive) { ModelKeys.remove(provider); dismiss() } }
                }
            }
            .navigationTitle(Text(verbatim: provider.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!canSave) }
            }
        }
    }

    private var canSave: Bool {
        provider == .custom ? URL(string: url.trimmingCharacters(in: .whitespaces))?.scheme?.hasPrefix("http") == true && !modelID.trimmingCharacters(in: .whitespaces).isEmpty : !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        do {
            if provider == .custom {
                ModelKeys.customURL = url.trimmingCharacters(in: .whitespaces)
                ModelKeys.customModel = modelID.trimmingCharacters(in: .whitespaces)
                if key.isEmpty { ModelKeys.selectedProvider = .custom }
            }
            if !key.isEmpty { try ModelKeys.save(key, for: provider) }
            // A new key picks its provider; the model page's picker switches between providers with keys.
            if provider.wired, !key.isEmpty { ModelKeys.selectedProvider = provider }
            key = ""
            dismiss()
        } catch {
            failed = true
        }
    }
}
