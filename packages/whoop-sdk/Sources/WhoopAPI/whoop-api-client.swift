import Foundation

/// Async client for the official WHOOP REST API v2.
///
/// Ported from felixnext/whoopy, gabrielmbmb/whoop-client, and developer.whoop.com OpenAPI spec.
public actor WhoopAPIClient {
    public static let baseURL = URL(string: "https://api.prod.whoop.com/developer/v2")!

    private var token: WhoopOAuthToken?
    private let clientID: String?
    private let clientSecret: String?
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(token: WhoopOAuthToken? = nil, clientID: String? = nil, clientSecret: String? = nil, session: URLSession = .shared) {
        self.token = token
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func setToken(_ token: WhoopOAuthToken) {
        self.token = token
    }

    public var currentToken: WhoopOAuthToken? { token }

    // MARK: - User

    public func getProfile() async throws -> WhoopUserProfile {
        try await get("user/profile/basic", as: WhoopUserProfile.self)
    }

    public func getBodyMeasurement() async throws -> WhoopBodyMeasurement {
        try await get("user/measurement/body", as: WhoopBodyMeasurement.self)
    }

    // MARK: - Cycles

    public func getCycles(start: Date? = nil, end: Date? = nil, limit: Int = 25, nextToken: String? = nil) async throws -> WhoopPaginatedCycles {
        try await getPaginated("cycle", start: start, end: end, limit: limit, nextToken: nextToken)
    }

    public func getAllCycles(start: Date? = nil, end: Date? = nil, maxRecords: Int? = nil) async throws -> [WhoopCycle] {
        try await getAll("cycle", start: start, end: end, maxRecords: maxRecords)
    }

    public func getCycle(id: Int) async throws -> WhoopCycle {
        try await get("cycle/\(id)", as: WhoopCycle.self)
    }

    public func getCycleSleep(cycleID: Int) async throws -> WhoopSleep {
        try await get("cycle/\(cycleID)/sleep", as: WhoopSleep.self)
    }

    public func getCycleRecovery(cycleID: Int) async throws -> WhoopRecovery {
        try await get("activity/recovery/cycle/\(cycleID)/recovery", as: WhoopRecovery.self)
    }

    // MARK: - Sleep

    public func getSleeps(start: Date? = nil, end: Date? = nil, limit: Int = 25, nextToken: String? = nil) async throws -> WhoopPaginatedSleeps {
        try await getPaginated("activity/sleep", start: start, end: end, limit: limit, nextToken: nextToken)
    }

    public func getAllSleeps(start: Date? = nil, end: Date? = nil, maxRecords: Int? = nil) async throws -> [WhoopSleep] {
        try await getAll("activity/sleep", start: start, end: end, maxRecords: maxRecords)
    }

    public func getSleep(id: UUID) async throws -> WhoopSleep {
        try await get("activity/sleep/\(id.uuidString)", as: WhoopSleep.self)
    }

    // MARK: - Recovery

    public func getRecoveries(start: Date? = nil, end: Date? = nil, limit: Int = 25, nextToken: String? = nil) async throws -> WhoopPaginatedRecoveries {
        try await getPaginated("activity/recovery", start: start, end: end, limit: limit, nextToken: nextToken)
    }

    public func getAllRecoveries(start: Date? = nil, end: Date? = nil, maxRecords: Int? = nil) async throws -> [WhoopRecovery] {
        try await getAll("activity/recovery", start: start, end: end, maxRecords: maxRecords)
    }

    // MARK: - Workouts

    public func getWorkouts(start: Date? = nil, end: Date? = nil, limit: Int = 25, nextToken: String? = nil) async throws -> WhoopPaginatedWorkouts {
        try await getPaginated("activity/workout", start: start, end: end, limit: limit, nextToken: nextToken)
    }

    public func getAllWorkouts(start: Date? = nil, end: Date? = nil, maxRecords: Int? = nil) async throws -> [WhoopWorkout] {
        try await getAll("activity/workout", start: start, end: end, maxRecords: maxRecords)
    }

    public func getWorkout(id: UUID) async throws -> WhoopWorkout {
        try await get("activity/workout/\(id.uuidString)", as: WhoopWorkout.self)
    }

    // MARK: - Activity mapping

    public func getActivityMapping(v1ID: Int) async throws -> WhoopActivityMapping {
        try await get("v1/activity-mapping/\(v1ID)", as: WhoopActivityMapping.self)
    }

    public func revokeAccess() async throws {
        _ = try await request("DELETE", path: "user/access")
    }

    // MARK: - HTTP

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let data = try await request("GET", path: path)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw WhoopAPIError.decodingFailed(error.localizedDescription)
        }
    }

    private func getPaginated<T: Codable & Sendable>(
        _ path: String,
        start: Date?,
        end: Date?,
        limit: Int,
        nextToken: String?
    ) async throws -> WhoopPaginatedResponse<T> {
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(min(max(limit, 1), 25)))]
        if let start { items.append(URLQueryItem(name: "start", value: iso8601(start))) }
        if let end { items.append(URLQueryItem(name: "end", value: iso8601(end))) }
        if let nextToken { items.append(URLQueryItem(name: "nextToken", value: nextToken)) }
        let data = try await request("GET", path: path, query: items)
        do {
            return try decoder.decode(WhoopPaginatedResponse<T>.self, from: data)
        } catch {
            throw WhoopAPIError.decodingFailed(error.localizedDescription)
        }
    }

    private func getAll<T: Codable & Sendable>(
        _ path: String,
        start: Date?,
        end: Date?,
        maxRecords: Int?
    ) async throws -> [T] {
        var all: [T] = []
        var nextToken: String?
        repeat {
            let page: WhoopPaginatedResponse<T> = try await getPaginated(path, start: start, end: end, limit: 25, nextToken: nextToken)
            all.append(contentsOf: page.records)
            nextToken = page.nextToken
            if let maxRecords, all.count >= maxRecords {
                return Array(all.prefix(maxRecords))
            }
        } while nextToken != nil
        return all
    }

    @discardableResult
    private func request(_ method: String, path: String, query: [URLQueryItem] = []) async throws -> Data {
        try await ensureValidToken()
        guard let token else { throw WhoopAPIError.notAuthenticated }

        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw WhoopAPIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("\(token.tokenType) \(token.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WhoopAPIError.invalidResponse }

        if http.statusCode == 401, let refresh = token.refreshToken, let clientID, let clientSecret {
            self.token = try await WhoopOAuth.refreshToken(refresh, clientID: clientID, clientSecret: clientSecret)
            return try await self.request(method, path: path, query: query)
        }

        if http.statusCode == 429 {
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw WhoopAPIError.rateLimited(retryAfter: retry)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw WhoopAPIError.httpStatus(http.statusCode, data)
        }
        return data
    }

    private func ensureValidToken() async throws {
        guard var token else { throw WhoopAPIError.notAuthenticated }
        guard token.isExpired, let refresh = token.refreshToken, let clientID, let clientSecret else { return }
        token = try await WhoopOAuth.refreshToken(refresh, clientID: clientID, clientSecret: clientSecret)
        self.token = token
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
