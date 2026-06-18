import Foundation
import CryptoKit

public struct RemoteCommandEnvelope: Decodable, Sendable {
    public let payload: String
    public let signature: String
}

public struct RemoteCommand: Decodable, Sendable {
    public let commandID: String
    public let type: String
    public let params: [String: RemoteCommandValue]
    public let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case commandID = "command_id"
        case type
        case params
        case exp
    }

    public init(commandID: String, type: String, params: [String: RemoteCommandValue], expiresAt: Date) {
        self.commandID = commandID
        self.type = type
        self.params = params
        self.expiresAt = expiresAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        commandID = try c.decode(String.self, forKey: .commandID)
        type = try c.decode(String.self, forKey: .type)
        params = (try? c.decode([String: RemoteCommandValue].self, forKey: .params)) ?? [:]
        let exp = try c.decode(Int.self, forKey: .exp)
        expiresAt = Date(timeIntervalSince1970: TimeInterval(exp))
    }
}

public enum RemoteCommandValue: Decodable, Sendable {
    case string(String)
    case int(Int)
    case object([String: RemoteCommandValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let o = try? container.decode([String: RemoteCommandValue].self) {
            self = .object(o)
        } else {
            self = .string("")
        }
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var intValue: Int? {
        if case .int(let i) = self { return i }
        return nil
    }
}

public enum CommandExecutionResult: Sendable {
    case completed(message: String)
    case failed(code: String, message: String)
    case rejected(message: String)

    public var status: String {
        switch self {
        case .completed: return "completed"
        case .failed: return "failed"
        case .rejected: return "rejected"
        }
    }

    public var resultPayload: [String: String] {
        switch self {
        case .completed(let message):
            return ["message": message]
        case .failed(let code, let message):
            return ["code": code, "message": message]
        case .rejected(let message):
            return ["message": message]
        }
    }
}

public enum CommandEnvelopeVerifier {
    public static func verify(
        envelope: RemoteCommandEnvelope,
        secret: String
    ) -> RemoteCommand? {
        guard let raw = Data(base64URLEncoded: envelope.payload),
              let key = secret.data(using: .utf8) else {
            return nil
        }
        let expected = hmacSHA256Base64URL(data: raw, key: key)
        guard expected == envelope.signature else { return nil }
        return try? JSONDecoder().decode(RemoteCommand.self, from: raw)
    }

    private static func hmacSHA256Base64URL(data: Data, key: Data) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))
        return Data(mac).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var s = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = s.count % 4
        if rem > 0 { s += String(repeating: "=", count: 4 - rem) }
        self.init(base64Encoded: s)
    }
}
