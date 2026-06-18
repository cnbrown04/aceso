import Foundation

/// WHOOP 4.0 haptic pattern IDs (strap preset library indices).
///
/// Query the full table at runtime with `GET_ALL_HAPTICS_PATTERN` (opcode 80) on a bonded strap.
public enum WhoopHapticPattern4: UInt8, Sendable, CaseIterable {
    case alarm = 2

    /// Default loop count used by NOOP for a test buzz.
    public static let defaultLoops: UInt8 = 2
}

/// WHOOP 5.0 / MG haptic presets using DRV2625 effect ID sequences.
///
/// Opcode **19** (`runHapticPatternMaverick`) — not opcode 79, which 5.0 firmware rejects.
public enum WhoopHapticPreset5: Sendable {
    case notify
    case alarm
    case strong
    case gentle
    case custom(effectIDs: [UInt16], loopControl: UInt16 = 0, overallLoop: UInt8 = 1)

    /// 12-byte maverick haptic payload (before puffin frame padding).
    public var payload: [UInt8] {
        switch self {
        case .notify:
            return WhoopHaptics.maverickPayload(effectIDs: [47, 152])
        case .alarm:
            return WhoopHaptics.maverickPayload(effectIDs: [10, 6])
        case .strong:
            return WhoopHaptics.maverickPayload(effectIDs: [1, 6])
        case .gentle:
            return WhoopHaptics.maverickPayload(effectIDs: [3, 4])
        case .custom(let ids, let loopControl, let overallLoop):
            return WhoopHaptics.maverickPayload(
                effectIDs: ids, loopControl: loopControl, overallLoop: overallLoop
            )
        }
    }
}

public enum WhoopHaptics {
    /// WHOOP 4.0 payload for `RUN_HAPTICS_PATTERN` (opcode 79).
    public static func pattern4Payload(patternId: UInt8, loops: UInt8) -> [UInt8] {
        [patternId, loops, 0x00, 0x00, 0x00]
    }

    /// WHOOP 5.0 payload for `RUN_HAPTIC_PATTERN_MAVERICK` (opcode 19).
    ///
    /// Layout: `[0x01][up to 4 × u16 LE effect IDs in 8 bytes][loopControl u16 LE][overallLoop u8]`
    public static func maverickPayload(
        effectIDs: [UInt16],
        loopControl: UInt16 = 0,
        overallLoop: UInt8 = 1
    ) -> [UInt8] {
        var effects = [UInt8](repeating: 0, count: 8)
        for (i, id) in effectIDs.prefix(4).enumerated() {
            effects[i * 2] = UInt8(id & 0xFF)
            effects[i * 2 + 1] = UInt8(id >> 8)
        }
        return [0x01]
            + effects
            + [UInt8(loopControl & 0xFF), UInt8(loopControl >> 8)]
            + [overallLoop]
    }
}
