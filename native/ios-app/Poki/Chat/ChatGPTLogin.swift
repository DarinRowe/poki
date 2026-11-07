import AuthenticationServices
import Foundation
import PiSwiftAI
import SwiftUI

/// The ChatGPT sign-in: OpenAI's Sign in with ChatGPT for open-source apps
/// (developers.openai.com/siwc/token-sharing-open-source), through PiSwiftAI's `loginOpenAIChatGPT`.
/// The first sign-in registers Poki with `dynamic_agent_client` and this installation's id; the page
/// opens in ASWebAuthenticationSession and redirects to a listener inside Poki on
/// http://127.0.0.1:1455/auth/callback, the only redirect the flow accepts. The chat then runs on the
/// OpenAI API (Responses, store off) on the owner's ChatGPT plan. Poki does not use Codex's own client.
///
/// The tokens go into the keychain as one JSON item and are never printed or logged.
enum ChatGPTAccount {
    static func decode(_ stored: String) -> OAuthCredentials? {
        try? JSONDecoder().decode(OAuthCredentials.self, from: Data(stored.utf8))
    }

    static func save(_ credentials: OAuthCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        try ModelKeys.save(String(decoding: data, as: UTF8.self), for: .chatgpt)
    }

    static var signedIn: Bool { ModelKeys.key(.chatgpt).flatMap(decode)?.clientId?.isEmpty == false }

    /// This installation's id for OpenAI's registration (`ext_agent_host_id`), made once.
    static var installationID: String {
        if let id = UserDefaults.standard.string(forKey: "chat.installationID") { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: "chat.installationID")
        return id
    }
}

@MainActor
final class ChatGPTBrowserLogin: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var manual: CheckedContinuation<String, Error>?
    private let cancel = CancellationToken()

    struct Cancelled: LocalizedError { var errorDescription: String? { String(localized: "Sign-in was cancelled.") } }

    func signIn() async throws -> OAuthCredentials {
        let callbacks = OAuthLoginCallbacks(
            onAuth: { [weak self] info in self?.open(info.url) },
            // The listener answers first; this only ends when the owner closes the sign-in sheet.
            onPrompt: { [weak self] _ in
                try await withCheckedThrowingContinuation { continuation in self?.manual = continuation }
            },
            signal: cancel,
            getDeviceId: { [id = ChatGPTAccount.installationID] in id },
            agentName: "Poki"
        )
        defer { finish() }
        return try await loginOpenAIChatGPT(callbacks)
    }

    private func open(_ address: String) {
        guard let url = URL(string: address) else { return }
        let session = ASWebAuthenticationSession(url: url, callback: .customScheme("poki")) { [weak self] _, _ in
            // Closed by the owner (the redirect goes to the listener, not to this callback).
            Task { @MainActor in self?.closed() }
        }
        session.presentationContextProvider = self
        self.session = session
        session.start()
    }

    private func closed() {
        session = nil
        manual?.resume(throwing: Cancelled())
        manual = nil
        cancel.cancel()
    }

    private func finish() {
        session?.cancel()
        session = nil
        manual?.resume(throwing: Cancelled())
        manual = nil
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}

/// The ChatGPT row's sheet: sign in, or sign out.
struct ChatGPTSignIn: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var working = false
    @State private var problem: String?
    @State private var login = ChatGPTBrowserLogin()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Continue with ChatGPT") { run { try await login.signIn() } }.disabled(working)
                } footer: {
                    Text("Poki uses your ChatGPT Plus or Pro plan through OpenAI’s Sign in with ChatGPT. The sign-in stays in this iPhone’s Keychain. An OpenAI API key works too, as a backup: add it under OpenAI.")
                }
                if let problem { Text(verbatim: problem).foregroundStyle(Color(.systemRed)) }
                if ChatGPTAccount.signedIn {
                    Section { Button("Sign Out", role: .destructive) { ModelKeys.remove(.chatgpt); dismiss() } }
                }
            }
            .navigationTitle(Text(verbatim: "ChatGPT"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func run(_ signIn: @escaping () async throws -> OAuthCredentials) {
        problem = nil
        working = true
        Task {
            do { done(try await signIn()) } catch { problem = error.localizedDescription }
            working = false
        }
    }

    private func done(_ credentials: OAuthCredentials) {
        do {
            try ChatGPTAccount.save(credentials)
            ModelKeys.selectedProvider = .chatgpt
            dismiss()
        } catch {
            problem = String(localized: "The keychain did not take the sign-in. Try again.")
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Simulator test runs only: `SIMCTL_CHILD_POKI_TEST_CREDENTIAL=<file>` names a JSON file on the Mac,
/// `{"provider": "chatgpt"|"anthropic"|…, "model"?: id, "secret": key or credential JSON}`. It is read
/// once at launch into the keychain and the provider is selected. Nothing is printed.
enum TestCredential {
    static func importIfGiven() {
        guard let path = ProcessInfo.processInfo.environment["POKI_TEST_CREDENTIAL"],
              let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let provider = (json["provider"] as? String).flatMap(ModelProvider.init(rawValue:)),
              let secret = json["secret"] as? String else { return }
        try? ModelKeys.save(secret, for: provider)
        ModelKeys.selectedProvider = provider
        if let model = json["model"] as? String { ModelKeys.selectedModel = model }
    }
}
#endif
