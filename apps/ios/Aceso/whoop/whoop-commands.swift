import Foundation

/// WHOOP command codes (on-wire values, shared between 4.0 and 5.0).
///
/// Only safe, non-destructive commands are listed. Destructive commands
/// (reboot, firmware load, power-cycle, BLE DFU) are intentionally excluded.
enum WhoopCommand: UInt8 {
    case toggleRealtimeHR     = 3
    case reportVersionInfo    = 7
    case setClock             = 10
    case getClock             = 11
    case sendHistoricalData   = 22
    case historicalDataResult = 23
    case getBatteryLevel      = 26
    case getDataRange         = 34
    case getHello             = 35
    case exitHighFreqSync     = 97  // sent defensively on connect to release a stuck strap
    case getExtendedBatteryInfo = 98

    /// COMMAND packet type byte (0x23 = 35) used in the inner bytes of every command frame.
    static let commandPacketType: UInt8 = 35

    // MARK: - WHOOP 4.0 frame

    /// Build a complete WHOOP 4.0 command frame.
    ///
    /// Layout: [0xAA][len u16 LE][CRC8(len)][type=35][seq][cmd][payload…][CRC32(inner) u32 LE]
    func frame4(seq: UInt8, payload: [UInt8] = [0x00]) -> [UInt8] {
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

    // MARK: - WHOOP 5.0 (puffin) frame

    /// Build a WHOOP 5.0 puffin command frame.
    ///
    /// Layout:
    ///   [0xAA][0x01][declLen u16 LE][0x00][seq][CRC16(header6) u16 LE][inner…pad4][CRC32(inner) u32 LE]
    ///
    /// Inner bytes = [type=35][seq][cmd][payload…] padded to the next 4-byte boundary.
    /// declaredLength = inner.count + 4.
    func frame5(seq: UInt8, payload: [UInt8] = [0x00]) -> [UInt8] {
        var inner: [UInt8] = [Self.commandPacketType, seq, rawValue] + payload
        // Pad inner to a 4-byte boundary (required by the puffin protocol).
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

    /// Build a command frame for the given device family.
    func frame(seq: UInt8, payload: [UInt8] = [0x00], family: WhoopDeviceFamily) -> [UInt8] {
        switch family {
        case .whoop4: return frame4(seq: seq, payload: payload)
        case .whoop5: return frame5(seq: seq, payload: payload)
        }
    }

    // MARK: - Payload builders

    /// SET_CLOCK payload: epoch as u32 LE followed by 4 zero subsecond bytes.
    ///
    /// Must be exactly 8 bytes. An un-clocked WHOOP 5 discards sensor data
    /// ("RTC timestamp is invalid; not saving data to flash").
    static func setClockPayload(at date: Date = Date()) -> [UInt8] {
        let epoch = UInt32(date.timeIntervalSince1970)
        return [UInt8(epoch & 0xFF), UInt8((epoch >> 8) & 0xFF),
                UInt8((epoch >> 16) & 0xFF), UInt8((epoch >> 24) & 0xFF),
                0x00, 0x00, 0x00, 0x00]
    }

    /// HISTORICAL_DATA_RESULT payload: acknowledges a HISTORY_END frame and advances the trim cursor.
    static func historicalDataResultPayload(trim: UInt32) -> [UInt8] {
        [0x01,
         UInt8(trim & 0xFF), UInt8((trim >> 8) & 0xFF),
         UInt8((trim >> 16) & 0xFF), UInt8((trim >> 24) & 0xFF)]
    }
}
