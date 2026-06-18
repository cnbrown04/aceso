import Foundation

public enum WhoopAPIError: Error, Sendable, LocalizedError {
    case notAuthenticated
    case invalidResponse
    case httpStatus(Int, Data?)
    case tokenRefreshFailed
    case rateLimited(retryAfter: Int?)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "No valid WHOOP OAuth token."
        case .invalidResponse: return "Invalid response from WHOOP API."
        case .httpStatus(let code, _): return "WHOOP API returned HTTP \(code)."
        case .tokenRefreshFailed: return "Failed to refresh WHOOP OAuth token."
        case .rateLimited(let retry): return "Rate limited\(retry.map { " — retry after \($0)s" } ?? "")."
        case .decodingFailed(let detail): return "Failed to decode WHOOP response: \(detail)"
        }
    }
}
