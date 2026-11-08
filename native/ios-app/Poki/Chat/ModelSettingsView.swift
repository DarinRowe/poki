// The model page combines two files from lhuanyu/OllamaMessage (commit c857a02), Copyright (c) 2023
// Huanyu Luo, MIT License; see THIRD_PARTY_NOTICES.md:
// - OllamaMessage/Class/View/MessageList/DialogueSettingsView.swift: the "Model" row with its label and a hidden-label
//   Picker on the right;
// - OllamaMessage/Class/View/DialogueList/OllamaModelSelectionView.swift: one row per provider with its 30 pt icon, the
//   whole row tappable, and the footer under the list.
// Changed: the ESP-171 board "M Model" (the grouped rows, the provider tiles, "Add Key"), keys entered
// into the keychain instead of a server's model list, and the agents on a computer below.
import SwiftUI

struct ModelSettingsView: View {
    var openAgents: () -> Void
    @State private var model = "\(ModelKeys.selectedProvider.rawValue)/\(ModelKeys.selectedModel)"
    @State private var editing: ModelProvider?
    @State private var signingIn = false
    @State private var version = ModelKeys.saved

    var body: some View {
        Form {
            Section {
                Picker("Model", selection: $model) {
                    ForEach(ModelProvider.allCases.filter(\.wired)) { provider in
                        ForEach(provider.models) { choice in
                            Text(choice.name).tag("\(provider.rawValue)/\(choice.id)")
                        }
                    }
                }
                .onChange(of: model) { _, new in
                    let parts = new.split(separator: "/", maxSplits: 1).map(String.init)
                    guard parts.count == 2, let provider = ModelProvider(rawValue: parts[0]) else { return }
                    ModelKeys.selectedProvider = provider
                    ModelKeys.selectedModel = parts[1]
                }
            } footer: {
                Text("The model Poki’s text chat uses.")
            }

            Section {
                LabeledContent("Text Chat", value: ModelKeys.hasUsableKey ? ModelKeys.selectedModelName : String(localized: "Not Set Up"))
                LabeledContent("Live Voice", value: VoiceDirect.apiKey != nil ? String(localized: "OpenAI API key") : String(localized: "Needs an OpenAI API key"))
                LabeledContent("Dictation", value: String(localized: "On this iPhone"))
            } header: {
                Text("What Each Uses")
            } footer: {
                Text("A ChatGPT sign-in or any key runs the text chat. Live voice needs OpenAI’s Realtime API, so it needs an OpenAI API key (or the Mac voice bridge). Dictation needs no key.")
            }

            Section {
                ForEach(ModelProvider.allCases) { provider in providerRow(provider) }
            } header: {
                Text("Your API Key")
            } footer: {
                Text("Keys stay in this iPhone’s Keychain. Poki sends each key only to its own provider.")
            }

            Section {
                agentRow("Claude Code", tile: 0xD97757)
                agentRow("Codex", tile: 0x111111)
            } header: {
                Text("Or Use an Agent You Already Run")
            } footer: {
                Text("Your computer does the thinking. Poki only taps and types.")
            }
        }
        .id(version)
        .navigationTitle("Model")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing, onDismiss: { version = ModelKeys.saved }) { provider in KeyEntry(provider: provider) }
        .sheet(isPresented: $signingIn, onDismiss: { version = ModelKeys.saved; model = "\(ModelKeys.selectedProvider.rawValue)/\(ModelKeys.selectedModel)" }) { ChatGPTSignIn() }
    }

    private func providerRow(_ provider: ModelProvider) -> some View {
        let hasKey = provider == .custom ? !ModelKeys.customURL.isEmpty : provider == .chatgpt ? ChatGPTAccount.signedIn : ModelKeys.hasKey(provider)
        return Button { if provider.signsIn { signingIn = true } else { editing = provider } } label: {
            HStack(spacing: 12) {
                ProviderTile(provider: provider)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: provider.name).foregroundStyle(Color(.label))
                    if provider == .custom {
                        Text(hasKey ? ModelKeys.customURL : String(localized: "Any OpenAI-compatible URL")).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                if hasKey {
                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint)
                        .accessibilityLabel(provider.signsIn ? Text("Signed in") : Text("Key added"))
                } else {
                    Text(provider == .custom ? "Add URL" : provider.signsIn ? "Sign In" : "Add Key").foregroundStyle(.tint)
                }
            }
        }
    }

    private func agentRow(_ name: String, tile: UInt32) -> some View {
        Button(action: openAgents) {
            HStack(spacing: 12) {
                Image(systemName: "terminal.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 29, height: 29).background(Color(hex: tile), in: .rect(cornerRadius: 7, style: .continuous))
                LabeledContent(name, value: String(localized: "Via Relay")).foregroundStyle(Color(.label))
            }
        }
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
