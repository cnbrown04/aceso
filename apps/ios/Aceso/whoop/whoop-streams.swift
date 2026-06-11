import Foundation

// MARK: - Sample types

struct WhoopHRSample: Codable {
    let ts: Int     // unix seconds
    let bpm: Int
}

struct WhoopRRInterval: Codable {
    let ts: Int     // unix seconds
    let rrMs: Int

    enum CodingKeys: String, CodingKey {
        case ts
        case rrMs = "rr_ms"
    }
}

struct WhoopBatterySample: Codable {
    let ts: Int     // unix seconds
    let pct: Double // 0–100
}

// MARK: - Batch

/// A batch of WHOOP samples ready to send to the server.
struct WhoopSampleBatch: Codable {
    let deviceID: String
    var hrSamples: [WhoopHRSample]
    var rrIntervals: [WhoopRRInterval]
    var batterySamples: [WhoopBatterySample]

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case hrSamples = "hr_samples"
        case rrIntervals = "rr_intervals"
        case batterySamples = "battery_samples"
    }

    var isEmpty: Bool {
        hrSamples.isEmpty && rrIntervals.isEmpty && batterySamples.isEmpty
    }
}

// MARK: - Standard BLE Heart Rate parser (characteristic 0x2A37)

enum StandardHeartRate {
    /// Parse a raw 0x2A37 notification value into BPM and R-R intervals (ms).
    static func parse(_ data: [UInt8]) -> (hr: Int, rr: [Int])? {
        guard !data.isEmpty else { return nil }
        let flags = data[0]
        var idx = 1
        let hr: Int
        if flags & 0x01 != 0 {
            guard idx + 1 < data.count else { return nil }
            hr = Int(data[idx]) | (Int(data[idx + 1]) << 8); idx += 2
        } else {
            guard idx < data.count else { return nil }
            hr = Int(data[idx]); idx += 1
        }
        if flags & 0x08 != 0 { idx += 2 }  // skip Energy Expended field
        var rr: [Int] = []
        if (flags >> 4) & 0x01 != 0 {      // R-R present (bit 4)
            while idx + 1 < data.count {
                let raw = Int(data[idx]) | (Int(data[idx + 1]) << 8)
                // 0x2A37 R-R units are 1/1024 seconds; convert to ms.
                rr.append(Int((Double(raw) / 1024.0 * 1000.0).rounded()))
                idx += 2
            }
        }
        return (hr, rr)
    }
}

// MARK: - Custom WHOOP frame decoder

/// Packet type bytes used in WHOOP 4.0 frames.
enum WhoopPacketType: UInt8 {
    case command         = 35
    case commandResponse = 36
    case realtimeData    = 40
    case realtimeRaw     = 43
    case historicalData  = 47
    case event           = 48
    case metadata        = 49
}

/// Decoded payload from a WHOOP custom protocol frame.
enum WhoopFramePayload {
    case realtimeHR(bpm: Int, rrMs: [Int], ts: Int)
    case batteryLevel(pct: Double)
    case historicalData(raw: [UInt8])   // full frame bytes for future deeper decode
    case unknown
}

/// Decode the payload of an already-verified WHOOP 4.0 frame.
///
/// Frame layout (confirmed against NOOP's whoop_protocol.json):
///   [4]     packet type (u8)
///   [5]     sequence (u8)
///   [6+]    packet-specific payload
func decodeWhoopFrame(_ frame: [UInt8]) -> WhoopFramePayload {
    guard frame.count >= 7 else { return .unknown }
    let type = frame[4]
    switch WhoopPacketType(rawValue: type) {

    case .realtimeData:
        // [6..9] timestamp u32 LE, [12] heart_rate u8, [13] rr_count u8, [14..] rr u16 LE each (ms)
        guard frame.count >= 13 else { return .unknown }
        let bpm = Int(frame[12])
        guard bpm >= 30, bpm <= 220 else { return .unknown }
        let ts  = Int(frame[6]) | (Int(frame[7]) << 8) | (Int(frame[8]) << 16) | (Int(frame[9]) << 24)
        let rrCount = Int(frame[13])
        var rrMs: [Int] = []
        for i in 0..<rrCount {
            let off = 14 + i * 2
            guard off + 1 < frame.count else { break }
            let v = Int(frame[off]) | (Int(frame[off + 1]) << 8)
            if v > 0 { rrMs.append(v) }
        }
        return .realtimeHR(bpm: bpm, rrMs: rrMs, ts: ts)

    case .commandResponse:
        // [6] resp_cmd u8, [7+] response payload
        // GET_BATTERY_LEVEL (26) response: payload[2..3] = pct * 10 u16 LE
        guard frame.count >= 7 else { return .unknown }
        let respCmd = frame[6]
        if respCmd == 26, frame.count >= 11 { // GET_BATTERY_LEVEL
            let raw = Int(frame[9]) | (Int(frame[10]) << 8)
            return .batteryLevel(pct: Double(raw) / 10.0)
        }
        return .unknown

    case .historicalData:
        return .historicalData(raw: frame)

    default:
        return .unknown
    }
}
