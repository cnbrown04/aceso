import Foundation

public enum WhoopConnectionState: Equatable, Sendable {
    case idle
    case scanning
    case connecting
    case connected
}

public enum WhoopSyncToastPhase: String, Sendable {
    case syncing
    case synced
    case failed
}

public struct WhoopSyncToast: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let phase: WhoopSyncToastPhase
    public let title: String
    public let detail: String

    public init(phase: WhoopSyncToastPhase, title: String, detail: String) {
        self.phase = phase
        self.title = title
        self.detail = detail
    }
}
