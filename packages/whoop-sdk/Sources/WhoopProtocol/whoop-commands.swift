import Foundation

/// WHOOP command codes (on-wire values, shared between 4.0 and 5.0).
///
/// Only safe, non-destructive commands are listed. Destructive commands
/// (reboot, firmware load, power-cycle, BLE DFU) are intentionally excluded.
public enum WhoopCommand: UInt8, Sendable {
    case linkValid = 1
    case toggleRealtimeHR = 3
    case reportVersionInfo = 7
    case setClock = 10
    case getClock = 11
    case sendHistoricalData = 22
    case historicalDataResult = 23
    case getBatteryLevel = 26
    case getDataRange = 34
    case getHelloHarvard = 35
    case setLedDrive = 39
    case getLedDrive = 40
    case setTiaGain = 41
    case getTiaGain = 42
    case setBiasOffset = 43
    case getBiasOffset = 44
    case sendR10R11Realtime = 63
    case setAlarmTime = 66
    case getAlarmTime = 67
    case runAlarm = 68
    case disableAlarm = 69
    case getAdvertisingNameHarvard = 76
    case runHapticPatternMaverick = 19
    case runHapticsPattern = 79
    case getAllHapticsPattern = 80
    case startRawData = 81
    case stopRawData = 82
    case getBodyLocationAndStatus = 84
    case enterHighFreqSync = 96
    case exitHighFreqSync = 97
    case getExtendedBatteryInfo = 98
    case calibrateCapsense = 100
    case toggleImuModeHistorical = 105
    case toggleImuMode = 106
    case enableOpticalData = 107
    case stopHaptics = 122
    case selectWrist = 123

    public static let commandPacketType: UInt8 = 35

    public func frame4(seq: UInt8, payload: [UInt8] = [0x00]) -> [UInt8] {
        let inner: [UInt8] = [Self.commandPacketType, seq, rawValue] + payload
        let length = UInt16(inner.count + 4)
        let lenBytes: [UInt8] = [UInt8(length & 0xFF), UInt8(length >> 8)]
        let headerCRC = whoopCRC8(lenBytes)
        let crc = whoopCRC32(inner)
        let trailer: [UInt8] = [
            UInt8(crc & 0xFF), UInt8((crc >> 8) & 0xFF),
            UInt8((crc >> 16) & 0xFF), UInt8((crc >> 24) & 0xFF),
        ]
        return [0xAA] + lenBytes + [headerCRC] + inner + trailer
    }

    public func frame5(seq: UInt8, payload: [UInt8] = [0x00]) -> [UInt8] {
        var inner: [UInt8] = [Self.commandPacketType, seq, rawValue] + payload
        while inner.count % 4 != 0 { inner.append(0x00) }
        let declaredLength = UInt16(inner.count + 4)
        let headerPrefix: [UInt8] = [
            0xAA, 0x01,
            UInt8(declaredLength & 0xFF), UInt8(declaredLength >> 8),
            0x00, seq,
        ]
        let headerCRC = whoopCRC16Modbus(headerPrefix)
        let crc = whoopCRC32(inner)
        let trailer: [UInt8] = [
            UInt8(crc & 0xFF), UInt8((crc >> 8) & 0xFF),
            UInt8((crc >> 16) & 0xFF), UInt8((crc >> 24) & 0xFF),
        ]
        return headerPrefix + [UInt8(headerCRC & 0xFF), UInt8(headerCRC >> 8)] + inner + trailer
    }

    public func frame(seq: UInt8, payload: [UInt8] = [0x00], family: WhoopDeviceFamily) -> [UInt8] {
        switch family {
        case .whoop4: return frame4(seq: seq, payload: payload)
        case .whoop5: return frame5(seq: seq, payload: payload)
        }
    }

    public static func setClockPayload(at date: Date = Date()) -> [UInt8] {
        let epoch = UInt32(date.timeIntervalSince1970)
        return [UInt8(epoch & 0xFF), UInt8((epoch >> 8) & 0xFF),
                UInt8((epoch >> 16) & 0xFF), UInt8((epoch >> 24) & 0xFF),
                0x00, 0x00, 0x00, 0x00]
    }

    public static func historicalDataResultPayload(trim: UInt32) -> [UInt8] {
        [0x01,
         UInt8(trim & 0xFF), UInt8((trim >> 8) & 0xFF),
         UInt8((trim >> 16) & 0xFF), UInt8((trim >> 24) & 0xFF)]
    }

    public static func setAlarmPayload(epochSec: UInt32) -> [UInt8] {
        [0x01,
         UInt8(epochSec & 0xFF), UInt8((epochSec >> 8) & 0xFF),
         UInt8((epochSec >> 16) & 0xFF), UInt8((epochSec >> 24) & 0xFF),
         0x00, 0x00]
    }
}
