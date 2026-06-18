import Foundation

/// Which WHOOP hardware generation a connection belongs to.
public enum WhoopDeviceFamily: String, Sendable, CaseIterable {
    case whoop4
    case whoop5

    /// Primary GATT service UUID string (lowercase, as advertised by the strap).
    public var serviceUUID: String {
        switch self {
        case .whoop4: return "61080001-8d6d-82b8-614a-1c8cb0f8dcc6"
        case .whoop5: return "fd4b0001-cce1-4033-93ce-002d5875f58a"
        }
    }

    /// Command-write characteristic UUID.
    public var commandCharUUID: String {
        switch self {
        case .whoop4: return "61080002-8d6d-82b8-614a-1c8cb0f8dcc6"
        case .whoop5: return "fd4b0002-cce1-4033-93ce-002d5875f58a"
        }
    }

    /// Notify characteristic UUIDs to subscribe for incoming data.
    public var notifyCharUUIDs: [String] {
        switch self {
        case .whoop4: return [
            "61080003-8d6d-82b8-614a-1c8cb0f8dcc6",
            "61080004-8d6d-82b8-614a-1c8cb0f8dcc6",
            "61080005-8d6d-82b8-614a-1c8cb0f8dcc6",
        ]
        case .whoop5: return [
            "fd4b0003-cce1-4033-93ce-002d5875f58a",
            "fd4b0004-cce1-4033-93ce-002d5875f58a",
            "fd4b0005-cce1-4033-93ce-002d5875f58a",
            "fd4b0007-cce1-4033-93ce-002d5875f58a",
        ]
        }
    }

    /// Static CLIENT_HELLO frame for WHOOP 5.0 bonding.
    public var clientHello: [UInt8]? {
        switch self {
        case .whoop4: return nil
        case .whoop5: return [
            0xAA, 0x01, 0x08, 0x00, 0x00, 0x01, 0xE6, 0x71,
            0x23, 0x01, 0x91, 0x01, 0x36, 0x3E, 0x5C, 0x8D,
        ]
        }
    }

    /// Detect device family from an advertised or discovered service UUID.
    public static func from(serviceUUID: String) -> WhoopDeviceFamily? {
        let normalized = serviceUUID.lowercased()
        if normalized == WhoopDeviceFamily.whoop4.serviceUUID { return .whoop4 }
        if normalized == WhoopDeviceFamily.whoop5.serviceUUID { return .whoop5 }
        return nil
    }

    public static let heartRateServiceUUID = "180D"
    public static let heartRateCharUUID = "2A37"
    public static let batteryServiceUUID = "180F"
    public static let batteryCharUUID = "2A19"
}
