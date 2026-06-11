import Foundation

/// Which WHOOP hardware generation a connection belongs to.
enum WhoopDeviceFamily {
    case whoop4
    case whoop5  // WHOOP 5.0 / MG ("puffin" protocol)

    /// Primary GATT service UUID string (lowercase, as advertised by the strap).
    var serviceUUID: String {
        switch self {
        case .whoop4: return "61080001-8d6d-82b8-614a-1c8cb0f8dcc6"
        case .whoop5: return "fd4b0001-cce1-4033-93ce-002d5875f58a"
        }
    }

    /// Command-write characteristic UUID.
    var commandCharUUID: String {
        switch self {
        case .whoop4: return "61080002-8d6d-82b8-614a-1c8cb0f8dcc6"
        case .whoop5: return "fd4b0002-cce1-4033-93ce-002d5875f58a"
        }
    }

    /// Notify characteristic UUIDs to subscribe for incoming data.
    ///
    /// WHOOP 5.0 has an extra 0007 char. All five chars must be subscribed AFTER bonding —
    /// the strap rejects them with "Authentication is insufficient" on an unencrypted link.
    var notifyCharUUIDs: [String] {
        switch self {
        case .whoop4: return [
            "61080003-8d6d-82b8-614a-1c8cb0f8dcc6",  // command responses
            "61080004-8d6d-82b8-614a-1c8cb0f8dcc6",  // events
            "61080005-8d6d-82b8-614a-1c8cb0f8dcc6",  // data (fragmented)
        ]
        case .whoop5: return [
            "fd4b0003-cce1-4033-93ce-002d5875f58a",
            "fd4b0004-cce1-4033-93ce-002d5875f58a",
            "fd4b0005-cce1-4033-93ce-002d5875f58a",
            "fd4b0007-cce1-4033-93ce-002d5875f58a",
        ]
        }
    }

    /// Bytes to write to the command characteristic immediately after GATT discovery.
    ///
    /// WHOOP 4.0: nil — the first bonded write (GET_BATTERY_LEVEL) serves as the handshake.
    /// WHOOP 5.0: a static CLIENT_HELLO (type-35 COMMAND, cmd GET_HELLO) written with .withResponse
    ///            triggers just-works bonding and opens the puffin session.
    var clientHello: [UInt8]? {
        switch self {
        case .whoop4: return nil
        case .whoop5: return [
            0xAA, 0x01, 0x08, 0x00, 0x00, 0x01, 0xE6, 0x71,
            0x23, 0x01, 0x91, 0x01, 0x36, 0x3E, 0x5C, 0x8D,
        ]
        }
    }

    // MARK: - Standard BLE service UUIDs (shared across generations)

    static let heartRateServiceUUID = "180D"
    static let heartRateCharUUID    = "2A37"  // HR measurement + R-R intervals
    static let batteryServiceUUID   = "180F"
    static let batteryCharUUID      = "2A19"  // battery level (0–100 %)
}
