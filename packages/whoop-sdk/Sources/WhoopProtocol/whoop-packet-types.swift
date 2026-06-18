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
    case strapDrivenAlarmSet = 56
    case strapDrivenAlarmExecuted = 57
    case appDrivenAlarmExecuted = 58
    case strapDrivenAlarmDisabled = 59
    case hapticsFired = 60
    case extendedBatteryInformation = 63
    case hapticsTerminated = 100
    case highFreqSyncPrompt = 96
    case highFreqSyncEnabled = 97
    case highFreqSyncDisabled = 98
}

public enum WhoopMetadataType: UInt8, Sendable {
    case historyStart = 1
    case historyEnd = 2
    case historyComplete = 3
}

/// Capabilities grouped by whether the strap must be bonded (encrypted link).
public enum WhoopBondRequirement: Sendable {
    /// Standard SIG services — work without custom-service bond.
    case unbonded
    /// Custom GATT service — requires just-works bond via confirmed command write.
    case bonded
}

/// Documents which SDK operations need a bonded strap.
public enum WhoopCapability: String, Sendable, CaseIterable {
    case liveHeartRateStandard = "live_hr_standard"
    case batteryStandard = "battery_standard"
    case liveHeartRateCustom = "live_hr_custom"
    case batteryCustom = "battery_custom"
    case historicalOffload = "historical_offload"
    case haptics = "haptics"
    case alarms = "alarms"
    case rawIMU = "raw_imu"
    case rawOptical = "raw_optical"
    case strapEvents = "strap_events"
    case consoleLogs = "console_logs"
    case setClock = "set_clock"
    case versionInfo = "version_info"
    case dataRange = "data_range"

    public var bondRequirement: WhoopBondRequirement {
        switch self {
        case .liveHeartRateStandard, .batteryStandard:
            return .unbonded
        default:
            return .bonded
        }
    }
}
