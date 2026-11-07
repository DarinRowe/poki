import AuthenticationServices
import Foundation
import PiSwiftAI
import SwiftUI

/// The ChatGPT sign-in: the same OAuth client and flow as pi's `/login` › ChatGPT on the Mac
/// (openai-codex), so the chat runs on the owner's ChatGPT subscription.
///
/// - Browser: PiSwiftAI's `loginOpenAICodex` listens on localhost:1455, the only redirect the client
///   accepts; the sign-in page opens in ASWebAuthenticationSession on this iPhone and redirects to that
///   listener inside Poki.
/// - Code: pi-ai's device code flow (`@earendil-works/pi-ai` 1.5.0, `dist/auth/oauth/openai-codex.js`,
///   MIT), ported below. It needs no redirect; the owner turns on device code sign-in for Codex in
///   ChatGPT's Security settings first.
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

    static var signedIn: Bool { ModelKeys.key(.chatgpt).flatMap(decode) != nil }
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
            signal: cancel
        )
        defer { finish() }
        return try await loginOpenAICodex(callbacks)
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

/// pi-ai's OpenAI Codex device code sign-in (openai-codex.js: startOpenAICodexDeviceAuth,
/// pollOpenAICodexDeviceAuth, exchangeAuthorizationCode).
enum ChatGPTDeviceLogin {
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let verificationURL = URL(string: "https://auth.openai.com/codex/device")!
    private static let userCodeURL = URL(string: "https://auth.openai.com/api/accounts/deviceauth/usercode")!
    private static let tokenURL = URL(string: "https://auth.openai.com/api/accounts/deviceauth/token")!
    private static let oauthTokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    private static let redirectURI = "https://auth.openai.com/deviceauth/callback"
    private static let timeout: TimeInterval = 15 * 60

    struct Device: Sendable { let id: String; let userCode: String; let interval: Double }

    struct Failure: LocalizedError { let errorDescription: String? }

    static func start() async throws -> Device {
        let (data, status) = try await post(userCodeURL, json: ["client_id": clientID])
        if status == 404 { throw Failure(errorDescription: String(localized: "OpenAI has not turned on code sign-in for this account. Use the browser sign-in.")) }
        guard (200..<300).contains(status), let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["device_auth_id"] as? String, let code = json["user_code"] as? String else {
            throw Failure(errorDescription: String(localized: "OpenAI did not give a sign-in code (\(status))."))
        }
        let interval = (json["interval"] as? NSNumber)?.doubleValue ?? Double((json["interval"] as? String)?.trimmingCharacters(in: .whitespaces) ?? "") ?? 5
        return Device(id: id, userCode: code, interval: max(interval, 1))
    }

    /// Polls until the owner approves the code, then exchanges it for tokens.
    static func finish(_ device: Device) async throws -> OAuthCredentials {
        let until = Date().addingTimeInterval(timeout)
        var interval = device.interval
        while Date() < until {
            try await Task.sleep(for: .seconds(interval))
            let (data, status) = try await post(tokenURL, json: ["device_auth_id": device.id, "user_code": device.userCode])
            if (200..<300).contains(status) {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let code = json["authorization_code"] as? String, let verifier = json["code_verifier"] as? String else {
                    throw Failure(errorDescription: String(localized: "OpenAI's answer to the sign-in code was not readable."))
                }
                return try await exchange(code: code, verifier: verifier)
            }
            if status == 403 || status == 404 { continue }
            let error = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"]
            let code = (error as? [String: Any])?["code"] as? String ?? error as? String
            if code == "deviceauth_authorization_pending" { continue }
            if code == "slow_down" { interval += 5; continue }
            throw Failure(errorDescription: String(localized: "OpenAI refused the sign-in code (\(status))."))
        }
        throw Failure(errorDescription: String(localized: "The sign-in code ran out. Start again."))
    }

    private static func exchange(code: String, verifier: String) async throws -> OAuthCredentials {
        var request = URLRequest(url: oauthTokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "grant_type", value: "authorization_code"), URLQueryItem(name: "client_id", value: clientID),
                           URLQueryItem(name: "code", value: code), URLQueryItem(name: "code_verifier", value: verifier),
                           URLQueryItem(name: "redirect_uri", value: redirectURI)]
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String, let refresh = json["refresh_token"] as? String,
              let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue,
              let account = accountID(access) else {
            throw Failure(errorDescription: String(localized: "OpenAI did not hand over the sign-in."))
        }
        return OAuthCredentials(refresh: refresh, access: access, expires: Date().timeIntervalSince1970 * 1000 + expiresIn * 1000, accountId: account)
    }

    /// The ChatGPT account id in the access token's claims (pi-ai `getAccountId`).
    static func accountID(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload), let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = claims["https://api.openai.com/auth"] as? [String: Any], let id = auth["chatgpt_account_id"] as? String, !id.isEmpty else { return nil }
        return id
    }

    private static func post(_ url: URL, json: [String: String]) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

/// The ChatGPT row's sheet: sign in with the browser, or with a code, or sign out.
struct ChatGPTSignIn: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var working = false
    @State private var device: ChatGPTDeviceLogin.Device?
    @State private var problem: String?
    @State private var login = ChatGPTBrowserLogin()
    @State private var polling: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Sign In with ChatGPT") { run { try await login.signIn() } }.disabled(working)
                } footer: {
                    Text("Poki uses your ChatGPT plan, the way Codex does. The sign-in stays in this iPhone’s Keychain.")
                }
                Section {
                    if let device {
                        Text(verbatim: device.userCode).font(.system(size: 28, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                            .accessibilityLabel(Text("Sign-in code \(device.userCode)"))
                        Button("Open the Sign-In Page") { openURL(ChatGPTDeviceLogin.verificationURL) }
                    } else {
                        Button("Use a Code Instead") { startCode() }.disabled(working)
                    }
                } footer: {
                    Text("For a code, first turn on device code sign-in for Codex in ChatGPT › Settings › Security. Then enter the code on auth.openai.com/codex/device.")
                }
                if let problem { Text(verbatim: problem).foregroundStyle(Color(.systemRed)) }
                if ChatGPTAccount.signedIn {
                    Section { Button("Sign Out", role: .destructive) { ModelKeys.remove(.chatgpt); dismiss() } }
                }
            }
            .navigationTitle(Text(verbatim: "ChatGPT"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { polling?.cancel(); dismiss() } } }
        }
    }

    private func startCode() {
        problem = nil
        working = true
        polling = Task {
            do {
                let started = try await ChatGPTDeviceLogin.start()
                device = started
                let credentials = try await ChatGPTDeviceLogin.finish(started)
                done(credentials)
            } catch is CancellationError {
            } catch {
                problem = error.localizedDescription
                device = nil
            }
            working = false
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
