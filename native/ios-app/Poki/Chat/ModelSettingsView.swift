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
    @Environment(\.dismiss) private var dismiss
    var openAgents: () -> Void
    @State private var model = "\(ModelKeys.selectedProvider.rawValue)/\(ModelKeys.selectedModel)"
    @State private var editing: ModelProvider?
    @State private var signingIn = false
    @State private var version = ModelKeys.saved

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: { Text(verbatim: "‹ Poki").font(.system(size: 17)).foregroundStyle(Site.blue) }
                        .buttonStyle(.plain).frame(width: 90, alignment: .leading)
                    Text("Model").font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity)
                    Color.clear.frame(width: 90, height: 1)
                }
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 14)

                // DialogueSettingsView's Model row.
                HStack {
                    Text("Model").font(.system(size: 17)).fixedSize()
                    Spacer()
                    Picker("Model", selection: $model) {
                        ForEach(ModelProvider.allCases.filter(\.wired)) { provider in
                            ForEach(provider.models) { choice in
                                Text(choice.name).tag("\(provider.rawValue)/\(choice.id)")
                            }
                        }
                    }
                    .labelsHidden()
                    .tint(ChatColor.secondary)
                }
                .padding(.vertical, 4).padding(.leading, 16).padding(.trailing, 4)
                .groupCard().padding(.horizontal, 16).padding(.bottom, 18)
                .onChange(of: model) { _, new in
                    let parts = new.split(separator: "/", maxSplits: 1).map(String.init)
                    guard parts.count == 2, let provider = ModelProvider(rawValue: parts[0]) else { return }
                    ModelKeys.selectedProvider = provider
                    ModelKeys.selectedModel = parts[1]
                }

                GroupedSection(title: "YOUR API KEY", footer: "Keys stay in this iPhone’s Keychain. Poki sends each key only to its own provider.") {
                    ForEach(Array(ModelProvider.allCases.enumerated()), id: \.element) { i, provider in
                        providerRow(provider).rowDivider(i < ModelProvider.allCases.count - 1)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 18)

                GroupedSection(title: "OR USE AN AGENT YOU ALREADY RUN", footer: "Your computer does the thinking. Poki only taps and types.") {
                    agentRow("Claude Code", tile: 0xD97757).rowDivider()
                    agentRow("Codex", tile: 0x111111)
                }
                .padding(.horizontal, 16).padding(.bottom, 32)
            }
            .id(version)
        }
        .background(Color(.systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editing, onDismiss: { version = ModelKeys.saved }) { provider in KeyEntry(provider: provider) }
        .sheet(isPresented: $signingIn, onDismiss: { version = ModelKeys.saved; model = "\(ModelKeys.selectedProvider.rawValue)/\(ModelKeys.selectedModel)" }) { ChatGPTSignIn() }
    }

    // OllamaModelSelectionView's row: icon, name, the whole row tappable.
    private func providerRow(_ provider: ModelProvider) -> some View {
        let hasKey = provider == .custom ? !ModelKeys.customURL.isEmpty : ModelKeys.hasKey(provider)
        return HStack(spacing: 12) {
            ProviderTile(provider: provider)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: provider.name).font(.system(size: 17)).foregroundStyle(Color(.label))
                if provider == .custom {
                    Text(hasKey ? ModelKeys.customURL : String(localized: "Any OpenAI-compatible URL")).font(.system(size: 13)).foregroundStyle(ChatColor.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if hasKey {
                Text(verbatim: "✓").font(.system(size: 17, weight: .semibold)).foregroundStyle(Site.blue)
                    .accessibilityLabel(provider.signsIn ? Text("Signed in") : Text("Key added"))
            } else {
                Text(provider == .custom ? "Add URL" : provider.signsIn ? "Sign In" : "Add Key").font(.system(size: 17)).foregroundStyle(Site.blue)
            }
        }
        .padding(.vertical, 9).padding(.horizontal, 16)
        .contentShape(.rect)
        .onTapGesture { if provider.signsIn { signingIn = true } else { editing = provider } }
        .accessibilityAddTraits(.isButton)
    }

    private func agentRow(_ name: String, tile: UInt32) -> some View {
        Button(action: openAgents) {
            HStack(spacing: 12) {
                Text(verbatim: ">_").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                    .frame(width: 29, height: 29).background(Color(hex: tile), in: .rect(cornerRadius: 7, style: .continuous))
                Text(verbatim: name).font(.system(size: 17)).foregroundStyle(Color(.label)).frame(maxWidth: .infinity, alignment: .leading)
                Text("Via Relay ›").font(.system(size: 17)).foregroundStyle(ChatColor.secondary)
            }
            .padding(.vertical, 9).padding(.horizontal, 16).contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Entering, replacing or removing one provider's key. The field is secure and the key is never shown
/// again after it is saved.
private struct KeyEntry: View {
    @Environment(\.dismiss) private var dismiss
    var provider: ModelProvider
    @State private var key = ""
    @State private var url = ModelKeys.customURL
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Form {
                if provider == .custom {
                    Section {
                        TextField("https://…/v1", text: $url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    } header: { Text("Address") }
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
        provider == .custom ? URL(string: url.trimmingCharacters(in: .whitespaces))?.scheme?.hasPrefix("http") == true : !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        do {
            if provider == .custom { ModelKeys.customURL = url.trimmingCharacters(in: .whitespaces) }
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
