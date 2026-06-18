import Foundation

public enum WhoopPacketType: UInt8, Sendable {
    case command = 35
    case commandResponse = 36
    case puffinCommand = 37
    case puffinCommandResponse = 38
    case realtimeData = 40
    case realtimeRaw = 43
    case historicalData = 47
    case event = 48
    case metadata = 49
    case consoleLogs = 50
    case realtimeImuStream = 51
    case historicalImuStream = 52
    case relativePuffinEvents = 53
    case puffinEventsFromStrap = 54
    case relativeBatteryPackConsoleLogs = 55
    case puffinMetadata = 56

    /// WHOOP 5.0 puffin types alias onto 4.0 semantics for unified decoding.
    public static func canonical(_ raw: UInt8) -> WhoopPacketType? {
        switch raw {
        case 38: return .commandResponse
        case 56: return .metadata
        default: return WhoopPacketType(rawValue: raw)
        }
    }
}

public enum WhoopEventNumber: UInt8, Sendable, Codable {
    case batteryLevel = 3
    case chargingOn = 7
    case chargingOff = 8
    case wristOn = 9
    case wristOff = 10
    case rtcLost = 13
    case doubleTap = 14
    case temperatureLevel = 17
    case bleBonded = 23
    case bleRealtimeHrOn = 33
    case bleRealtimeHrOff = 34
    case rawDataCollectionOn = 46
    case rawDataCollectionOff = 47
    case extendedBatteryInformation = 63
    case highFreqSyncPrompt = 96
    case highFreqSyncEnabled = 97
    case highFreqSyncDisabled = 98
}

public enum WhoopMetadataType: UInt8, Sendable {
    case historyStart = 1
    case historyEnd = 2
    case historyComplete = 3
}
