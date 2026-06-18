import Foundation

public struct WhoopOAuthToken: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let tokenType: String
    public let expiresAt: Date
    public let scopes: [String]

    public var isExpired: Bool { Date() >= expiresAt }

    public init(accessToken: String, refreshToken: String?, tokenType: String, expiresAt: Date, scopes: [String]) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.expiresAt = expiresAt
        self.scopes = scopes
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case scope
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try c.decode(String.self, forKey: .accessToken)
        refreshToken = try c.decodeIfPresent(String.self, forKey: .refreshToken)
        tokenType = try c.decodeIfPresent(String.self, forKey: .tokenType) ?? "Bearer"
        let expiresIn = try c.decodeIfPresent(Int.self, forKey: .expiresIn) ?? 3600
        expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        let scopeStr = try c.decodeIfPresent(String.self, forKey: .scope) ?? ""
        scopes = scopeStr.split(separator: " ").map(String.init)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(accessToken, forKey: .accessToken)
        try c.encodeIfPresent(refreshToken, forKey: .refreshToken)
        try c.encode(tokenType, forKey: .tokenType)
        try c.encode(max(0, Int(expiresAt.timeIntervalSinceNow)), forKey: .expiresIn)
        try c.encode(scopes.joined(separator: " "), forKey: .scope)
    }
}

public enum WhoopOAuth {
    public static let authorizationURL = URL(string: "https://api.prod.whoop.com/oauth/oauth2/auth")!
    public static let tokenURL = URL(string: "https://api.prod.whoop.com/oauth/oauth2/token")!

    public static let defaultScopes = [
        "read:recovery",
        "read:cycles",
        "read:workout",
        "read:sleep",
        "read:profile",
        "read:body_measurement",
        "offline",
    ]

    public static func authorizationURL(clientID: String, redirectURI: String, scopes: [String] = defaultScopes, state: String = UUID().uuidString) -> URL {
        var components = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    public static func exchangeCode(
        code: String,
        clientID: String,
        clientSecret: String,
        redirectURI: String
    ) async throws -> WhoopOAuthToken {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type=authorization_code",
            "code=\(code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code)",
            "client_id=\(clientID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clientID)",
            "client_secret=\(clientSecret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clientSecret)",
            "redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectURI)",
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WhoopAPIError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? 0, data)
        }
        return try JSONDecoder().decode(WhoopOAuthToken.self, from: data)
    }

    public static func refreshToken(
        _ refreshToken: String,
        clientID: String,
        clientSecret: String
    ) async throws -> WhoopOAuthToken {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type=refresh_token",
            "refresh_token=\(refreshToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? refreshToken)",
            "client_id=\(clientID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clientID)",
            "client_secret=\(clientSecret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clientSecret)",
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WhoopAPIError.tokenRefreshFailed
        }
        return try JSONDecoder().decode(WhoopOAuthToken.self, from: data)
    }
}

#if os(iOS)
import AuthenticationServices
import UIKit

@MainActor
public final class WhoopOAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let clientID: String
    private let clientSecret: String
    private let redirectURI: String

    public init(clientID: String, clientSecret: String, redirectURI: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
    }

    public func authenticate(scopes: [String] = WhoopOAuth.defaultScopes) async throws -> WhoopOAuthToken {
        let state = UUID().uuidString
        let authURL = WhoopOAuth.authorizationURL(clientID: clientID, redirectURI: redirectURI, scopes: scopes, state: state)
        let callbackScheme = URL(string: redirectURI)?.scheme ?? "whoop"

        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { url, error in
                if let error { continuation.resume(throwing: error); return }
                guard let url else {
                    continuation.resume(throwing: WhoopAPIError.notAuthenticated)
                    return
                }
                continuation.resume(returning: url)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            session.start()
        }

        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw WhoopAPIError.notAuthenticated
        }

        return try await WhoopOAuth.exchangeCode(
            code: code, clientID: clientID, clientSecret: clientSecret, redirectURI: redirectURI
        )
    }

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}
#endif
