import Foundation
import Combine
import AuthenticationServices
import CryptoKit
import Security

enum AuthError: LocalizedError {
    case missingConfiguration
    case authorizationFailed(String)
    case tokenExchangeFailed(String)
    case noToken
    case tokenRefreshFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration: return "Client ID and Tenant ID are required."
        case .authorizationFailed(let m): return "Authorization failed: \(m)"
        case .tokenExchangeFailed(let m): return "Token exchange failed: \(m)"
        case .noToken: return "Not authenticated. Please sign in."
        case .tokenRefreshFailed(let m): return "Token refresh failed: \(m)"
        }
    }
}

@MainActor
final class AuthManager: NSObject, ObservableObject {
    static let shared = AuthManager()

    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let redirectScheme = "msauth"
    private let redirectURI = "msauth://auth"
    private let scope = "https://graph.microsoft.com/AuditLog.Read.All offline_access"

    private var activeSession: ASWebAuthenticationSession?
    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    nonisolated override init() {
        super.init()
        // Defer main-actor work to after init completes
        Task { @MainActor [self] in
            self.checkAuthentication()
        }
    }

    var clientId: String {
        get { UserDefaults.standard.string(forKey: "clientId") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "clientId") }
    }

    var tenantId: String {
        get { UserDefaults.standard.string(forKey: "tenantId") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "tenantId") }
    }

    private func checkAuthentication() {
        guard let expiryString = try? KeychainHelper.load(key: "tokenExpiry"),
              let expiry = Double(expiryString)
        else {
            isAuthenticated = (try? KeychainHelper.load(key: "refreshToken")) != nil
            return
        }
        let hasValidAccess = Date().timeIntervalSince1970 < expiry
        let hasRefresh = (try? KeychainHelper.load(key: "refreshToken")) != nil
        isAuthenticated = hasValidAccess || hasRefresh
    }

    func signIn() async {
        guard !clientId.isEmpty, !tenantId.isEmpty else {
            errorMessage = "Please enter Client ID and Tenant ID in Settings."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let (code, verifier) = try await performAuthorizationRequest()
            try await exchangeCodeForTokens(code: code, verifier: verifier)
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func signOut() {
        KeychainHelper.delete(key: "accessToken")
        KeychainHelper.delete(key: "refreshToken")
        KeychainHelper.delete(key: "tokenExpiry")
        isAuthenticated = false
        errorMessage = nil
    }

    func getValidToken() async throws -> String {
        if let token = try? KeychainHelper.load(key: "accessToken"),
           let expiryString = try? KeychainHelper.load(key: "tokenExpiry"),
           let expiry = Double(expiryString),
           Date().timeIntervalSince1970 < expiry - 60 {
            return token
        }
        if let refreshToken = try? KeychainHelper.load(key: "refreshToken") {
            return try await refreshAccessToken(using: refreshToken)
        }
        throw AuthError.noToken
    }

    // MARK: - PKCE

    private func generateCodeVerifier() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AuthError.authorizationFailed("Failed to generate secure random bytes.")
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateState() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AuthError.authorizationFailed("Failed to generate CSRF state.")
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Authorization

    private func performAuthorizationRequest() async throws -> (code: String, verifier: String) {
        let codeVerifier = try generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        let state = try generateState()

        var components = URLComponents()
        components.scheme = "https"
        components.host = "login.microsoftonline.com"
        components.path = "/\(tenantId)/oauth2/v2.0/authorize"
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]

        guard let authURL = components.url else {
            throw AuthError.authorizationFailed("Could not construct authorization URL.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: redirectScheme
            ) { callbackURL, error in
                if let error = error {
                    let code = (error as? ASWebAuthenticationSessionError)?.code
                    if code == .canceledLogin {
                        continuation.resume(throwing: AuthError.authorizationFailed("Login was canceled."))
                    } else {
                        continuation.resume(throwing: AuthError.authorizationFailed(error.localizedDescription))
                    }
                    return
                }
                guard let callbackURL,
                      let comps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let authCode = comps.queryItems?.first(where: { $0.name == "code" })?.value,
                      let returnedState = comps.queryItems?.first(where: { $0.name == "state" })?.value,
                      returnedState == state
                else {
                    continuation.resume(throwing: AuthError.authorizationFailed("Invalid callback response."))
                    return
                }
                continuation.resume(returning: (code: authCode, verifier: codeVerifier))
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            session.start()
            self.activeSession = session
        }
    }

    // MARK: - Token Exchange

    private func exchangeCodeForTokens(code: String, verifier: String) async throws {
        let url = try buildTokenURL()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncode([
            "client_id": clientId,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": verifier,
            "scope": scope
        ])
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.tokenExchangeFailed("Token exchange failed. Please try signing in again.")
        }
        try storeTokenResponse(data: data)
    }

    private func refreshAccessToken(using refreshToken: String) async throws -> String {
        let url = try buildTokenURL()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncode([
            "client_id": clientId,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": scope
        ])
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            KeychainHelper.delete(key: "refreshToken")
            isAuthenticated = false
            throw AuthError.tokenRefreshFailed("Refresh token expired. Please sign in again.")
        }
        return try storeTokenResponse(data: data)
    }

    private func buildTokenURL() throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "login.microsoftonline.com"
        components.path = "/\(tenantId)/oauth2/v2.0/token"
        guard let url = components.url else {
            throw AuthError.tokenExchangeFailed("Could not construct token URL.")
        }
        return url
    }

    @discardableResult
    private func storeTokenResponse(data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String
        else {
            throw AuthError.tokenExchangeFailed("No access token in response.")
        }
        let expiresIn = json["expires_in"] as? Double ?? 3600
        let expiry = Date().timeIntervalSince1970 + expiresIn
        try KeychainHelper.save(key: "accessToken", value: accessToken)
        try KeychainHelper.save(key: "tokenExpiry", value: String(expiry))
        if let refreshToken = json["refresh_token"] as? String {
            try KeychainHelper.save(key: "refreshToken", value: refreshToken)
        }
        return accessToken
    }

    private func formEncode(_ params: [String: String]) -> Data? {
        var comps = URLComponents()
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        return comps.percentEncodedQuery?.data(using: .utf8)
    }
}

extension AuthManager: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApplication.shared.windows.first(where: { $0.isKeyWindow })
                ?? NSApplication.shared.windows.first
                ?? NSWindow()
        }
    }
}
