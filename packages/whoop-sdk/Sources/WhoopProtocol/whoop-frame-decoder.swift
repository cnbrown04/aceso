import Foundation

/// Decoded payload from a WHOOP custom protocol frame.
public enum WhoopFramePayload: Sendable {
    case realtimeHR(bpm: Int, rrMs: [Int], ts: Int)
    case batteryLevel(pct: Double)
    case extendedBattery(WhoopExtendedBattery)
    case versionInfo(WhoopVersionInfo)
    case dataRange(WhoopDataRange)
    case deviceClock(unix: UInt32)
    case rawIMU(WhoopIMUSample)
    case rawOptical(WhoopRawOpticalPacket)
    case strapEvent(WhoopStrapEvent)
    case historicalData(raw: [UInt8])
    case historyStart
    case historyEnd(trim: UInt32)
    case historyComplete
    case consoleLog(text: String)
    case alarmTime(WhoopAlarmTime)
    case hapticsPatterns(raw: [UInt8])
    case unknown(type: UInt8)
}

private func payloadOffset(in frame: [UInt8], family: WhoopDeviceFamily) -> Int {
    family == .whoop5 ? 8 : 4
}

private func readU16LE(_ bytes: [UInt8], _ offset: Int) -> Int? {
    guard offset + 1 < bytes.count else { return nil }
    return Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
}

private func readU32LE(_ bytes: [UInt8], _ offset: Int) -> UInt32? {
    guard offset + 3 < bytes.count else { return nil }
    return UInt32(bytes[offset])
        | (UInt32(bytes[offset + 1]) << 8)
        | (UInt32(bytes[offset + 2]) << 16)
        | (UInt32(bytes[offset + 3]) << 24)
}

/// Decode the payload of an already-verified WHOOP frame.
public func decodeWhoopFrame(_ frame: [UInt8], family: WhoopDeviceFamily = .whoop4) -> WhoopFramePayload {
    let base = payloadOffset(in: frame, family: family)
    guard frame.count >= base + 3 else { return .unknown(type: 0) }

    let rawType = frame[base]
    guard let packetType = WhoopPacketType.canonical(rawType) else {
        return .unknown(type: rawType)
    }

    switch packetType {
    case .realtimeData:
        guard frame.count >= base + 10 else { return .unknown(type: rawType) }
        let bpm = Int(frame[base + 6])
        guard bpm >= 30, bpm <= 220 else { return .unknown(type: rawType) }
        let ts = Int(readU32LE(frame, base + 2) ?? 0)
        let rrCount = Int(frame[base + 7])
        var rrMs: [Int] = []
        for i in 0..<rrCount {
            let off = base + 8 + i * 2
            guard let v = readU16LE(frame, off), v > 0 else { break }
            rrMs.append(v)
        }
        return .realtimeHR(bpm: bpm, rrMs: rrMs, ts: ts)

    case .commandResponse:
        guard frame.count >= base + 4 else { return .unknown(type: rawType) }
        let respCmd = frame[base + 2]
        let payStart = base + 3
        switch respCmd {
        case WhoopCommand.getBatteryLevel.rawValue:
            guard let raw = readU16LE(frame, payStart + 2) else { return .unknown(type: rawType) }
            return .batteryLevel(pct: Double(raw) / 10.0)
        case WhoopCommand.getExtendedBatteryInfo.rawValue:
            guard let mv = readU16LE(frame, payStart + 4) else { return .unknown(type: rawType) }
            let pctRaw = readU16LE(frame, payStart) ?? 0
            return .extendedBattery(WhoopExtendedBattery(pct: Double(pctRaw) / 10.0, millivolts: mv))
        case WhoopCommand.getClock.rawValue:
            guard let unix = readU32LE(frame, payStart) else { return .unknown(type: rawType) }
            return .deviceClock(unix: unix)
        case WhoopCommand.getDataRange.rawValue:
            guard let oldest = readU32LE(frame, payStart),
                  let newest = readU32LE(frame, payStart + 8) else { return .unknown(type: rawType) }
            return .dataRange(WhoopDataRange(oldestUnix: Int(oldest), newestUnix: Int(newest)))
        case WhoopCommand.reportVersionInfo.rawValue:
            let harvard = decodeVersionString(frame, start: payStart)
            let boylston = decodeVersionString(frame, start: payStart + 16)
            return .versionInfo(WhoopVersionInfo(harvard: harvard, boylston: boylston))
        case WhoopCommand.getAlarmTime.rawValue:
            guard let epoch = readU32LE(frame, payStart + 1) else { return .unknown(type: rawType) }
            return .alarmTime(WhoopAlarmTime(epochSec: epoch))
        case WhoopCommand.getAllHapticsPattern.rawValue:
            let end = max(payStart, frame.count - 4)
            return .hapticsPatterns(raw: Array(frame[payStart..<end]))
        default:
            return .unknown(type: rawType)
        }

    case .realtimeRaw, .historicalData:
        let dataLen = framePayloadLength(frame, family: family)
        if dataLen == WhoopRawDecoder.imuPacketDataLength {
            if let imu = WhoopRawDecoder.decodeIMUPacket(frame, family: family) {
                return .rawIMU(imu)
            }
        } else if dataLen == WhoopRawDecoder.opticalPacketDataLength {
            if let optical = WhoopRawDecoder.decodeOpticalPacket(frame, family: family) {
                return .rawOptical(optical)
            }
        }
        if packetType == .historicalData {
            return .historicalData(raw: frame)
        }
        return .unknown(type: rawType)

    case .realtimeImuStream:
        if let imu = WhoopRawDecoder.decodeVariableIMUPacket(frame, family: family) {
            return .rawIMU(imu)
        }
        return .unknown(type: rawType)

    case .event:
        return decodeEvent(frame, base: base) ?? .unknown(type: rawType)

    case .metadata:
        guard frame.count >= base + 3 else { return .unknown(type: rawType) }
        switch frame[base + 2] {
        case WhoopMetadataType.historyStart.rawValue:
            return .historyStart
        case WhoopMetadataType.historyEnd.rawValue:
            guard let trim = readU32LE(frame, base + 13) else { return .unknown(type: rawType) }
            return .historyEnd(trim: trim)
        case WhoopMetadataType.historyComplete.rawValue:
            return .historyComplete
        default:
            return .unknown(type: rawType)
        }

    case .consoleLogs:
        let textStart = base + 2
        guard textStart < frame.count else { return .unknown(type: rawType) }
        let text = String(bytes: frame[textStart..<frame.count - 4], encoding: .utf8) ?? ""
        return .consoleLog(text: text)

    default:
        return .unknown(type: rawType)
    }
}

private func framePayloadLength(_ frame: [UInt8], family: WhoopDeviceFamily) -> Int {
    switch family {
    case .whoop4:
        let length = Int(frame[1]) | (Int(frame[2]) << 8)
        return max(0, length - 7)
    case .whoop5:
        let declared = Int(frame[2]) | (Int(frame[3]) << 8)
        return max(0, declared - 8)
    }
}

private func decodeVersionString(_ frame: [UInt8], start: Int) -> String {
    guard start < frame.count else { return "" }
    let end = min(start + 16, frame.count)
    let slice = frame[start..<end]
    if let zero = slice.firstIndex(of: 0) {
        return String(bytes: slice[..<zero], encoding: .utf8) ?? ""
    }
    return String(bytes: slice, encoding: .utf8) ?? ""
}

private func decodeEvent(_ frame: [UInt8], base: Int) -> WhoopFramePayload? {
    guard frame.count >= base + 6,
          let event = WhoopEventNumber(rawValue: frame[base + 2]) else { return nil }
    let ts = Int(readU32LE(frame, base + 4) ?? 0)

    if event == .batteryLevel || event == .extendedBatteryInformation {
        let pctRaw = readU16LE(frame, base + 9) ?? 0
        let mv = readU16LE(frame, base + 13) ?? 0
        return .strapEvent(WhoopStrapEvent(
            event: event, ts: ts,
            batteryPct: Double(pctRaw) / 10.0,
            batteryMv: mv
        ))
    }

    return .strapEvent(WhoopStrapEvent(event: event, ts: ts))
}
