import Foundation

// MARK: - CRC8 (poly 0x07) — WHOOP 4.0 header check

// Lookup table ported verbatim from NOOP's WhoopProtocol/Framing.swift.
private let crc8Table: [UInt8] = [
    0x00, 0x07, 0x0E, 0x09, 0x1C, 0x1B, 0x12, 0x15, 0x38, 0x3F, 0x36, 0x31, 0x24, 0x23, 0x2A, 0x2D,
    0x70, 0x77, 0x7E, 0x79, 0x6C, 0x6B, 0x62, 0x65, 0x48, 0x4F, 0x46, 0x41, 0x54, 0x53, 0x5A, 0x5D,
    0xE0, 0xE7, 0xEE, 0xE9, 0xFC, 0xFB, 0xF2, 0xF5, 0xD8, 0xDF, 0xD6, 0xD1, 0xC4, 0xC3, 0xCA, 0xCD,
    0x90, 0x97, 0x9E, 0x99, 0x8C, 0x8B, 0x82, 0x85, 0xA8, 0xAF, 0xA6, 0xA1, 0xB4, 0xB3, 0xBA, 0xBD,
    0xC7, 0xC0, 0xC9, 0xCE, 0xDB, 0xDC, 0xD5, 0xD2, 0xFF, 0xF8, 0xF1, 0xF6, 0xE3, 0xE4, 0xED, 0xEA,
    0xB7, 0xB0, 0xB9, 0xBE, 0xAB, 0xAC, 0xA5, 0xA2, 0x8F, 0x88, 0x81, 0x86, 0x93, 0x94, 0x9D, 0x9A,
    0x27, 0x20, 0x29, 0x2E, 0x3B, 0x3C, 0x35, 0x32, 0x1F, 0x18, 0x11, 0x16, 0x03, 0x04, 0x0D, 0x0A,
    0x57, 0x50, 0x59, 0x5E, 0x4B, 0x4C, 0x45, 0x42, 0x6F, 0x68, 0x61, 0x66, 0x73, 0x74, 0x7D, 0x7A,
    0x89, 0x8E, 0x87, 0x80, 0x95, 0x92, 0x9B, 0x9C, 0xB1, 0xB6, 0xBF, 0xB8, 0xAD, 0xAA, 0xA3, 0xA4,
    0xF9, 0xFE, 0xF7, 0xF0, 0xE5, 0xE2, 0xEB, 0xEC, 0xC1, 0xC6, 0xCF, 0xC8, 0xDD, 0xDA, 0xD3, 0xD4,
    0x69, 0x6E, 0x67, 0x60, 0x75, 0x72, 0x7B, 0x7C, 0x51, 0x56, 0x5F, 0x58, 0x4D, 0x4A, 0x43, 0x44,
    0x19, 0x1E, 0x17, 0x10, 0x05, 0x02, 0x0B, 0x0C, 0x21, 0x26, 0x2F, 0x28, 0x3D, 0x3A, 0x33, 0x34,
    0x4E, 0x49, 0x40, 0x47, 0x52, 0x55, 0x5C, 0x5B, 0x76, 0x71, 0x78, 0x7F, 0x6A, 0x6D, 0x64, 0x63,
    0x3E, 0x39, 0x30, 0x37, 0x22, 0x25, 0x2C, 0x2B, 0x06, 0x01, 0x08, 0x0F, 0x1A, 0x1D, 0x14, 0x13,
    0xAE, 0xA9, 0xA0, 0xA7, 0xB2, 0xB5, 0xBC, 0xBB, 0x96, 0x91, 0x98, 0x9F, 0x8A, 0x8D, 0x84, 0x83,
    0xDE, 0xD9, 0xD0, 0xD7, 0xC2, 0xC5, 0xCC, 0xCB, 0xE6, 0xE1, 0xE8, 0xEF, 0xFA, 0xFD, 0xF4, 0xF3,
]

func whoopCRC8(_ bytes: [UInt8]) -> UInt8 {
    var crc: UInt8 = 0
    for b in bytes { crc = crc8Table[Int(crc ^ b)] }
    return crc
}

// MARK: - CRC16-Modbus (poly 0xA001, init 0xFFFF, reflected) — WHOOP 5.0 header check

func whoopCRC16Modbus(_ bytes: [UInt8]) -> UInt16 {
    var crc: UInt16 = 0xFFFF
    for b in bytes {
        crc ^= UInt16(b)
        for _ in 0..<8 {
            crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xA001 : crc >> 1
        }
    }
    return crc
}

// MARK: - CRC32 (zlib, reflected, poly 0xEDB88320) — payload integrity for both families

private let crc32Table: [UInt32] = {
    var t = [UInt32](repeating: 0, count: 256)
    for i in 0..<256 {
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        t[i] = c
    }
    return t
}()

func whoopCRC32(_ bytes: [UInt8]) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for b in bytes { crc = crc32Table[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8) }
    return crc ^ 0xFFFF_FFFF
}

// MARK: - Frame verification

struct WhoopFrameCheck {
    let ok: Bool
    let declaredLength: Int?
}

/// Verify a complete WHOOP 4.0 frame.
///
/// Layout: [0xAA][len u16 LE][CRC8(len)][…inner…][CRC32(inner) u32 LE]
/// Total bytes = len + 4, inner = frame[4..<len].
func verifyWhoopFrame4(_ frame: [UInt8]) -> WhoopFrameCheck {
    guard frame.count >= 8, frame[0] == 0xAA else { return WhoopFrameCheck(ok: false, declaredLength: nil) }
    let length = Int(frame[1]) | (Int(frame[2]) << 8)
    guard whoopCRC8([frame[1], frame[2]]) == frame[3] else { return WhoopFrameCheck(ok: false, declaredLength: length) }
    guard length >= 7, length <= 4096, length + 4 <= frame.count else { return WhoopFrameCheck(ok: false, declaredLength: length) }
    let inner = Array(frame[4..<length])
    let stored = UInt32(frame[length]) | (UInt32(frame[length+1]) << 8)
        | (UInt32(frame[length+2]) << 16) | (UInt32(frame[length+3]) << 24)
    return WhoopFrameCheck(ok: whoopCRC32(inner) == stored, declaredLength: length)
}

/// Verify a complete WHOOP 5.0 (puffin) frame.
///
/// Layout:
///   [0]     0xAA  SOF
///   [1]     0x01  format byte
///   [2-3]   declaredLength u16 LE  (= payloadLen + 4)
///   [4-5]   header fields (contains seq at [5])
///   [6-7]   CRC16-Modbus of frame[0..<6], u16 LE
///   [8..]   payload bytes (length = declaredLength - 4)
///   [tail]  CRC32(payload) u32 LE
///   Total bytes = declaredLength + 8
func verifyWhoopFrame5(_ frame: [UInt8]) -> WhoopFrameCheck {
    guard frame.count >= 12, frame[0] == 0xAA else { return WhoopFrameCheck(ok: false, declaredLength: nil) }
    let declaredLength = Int(frame[2]) | (Int(frame[3]) << 8)
    guard declaredLength >= 4, declaredLength <= 4096 else { return WhoopFrameCheck(ok: false, declaredLength: declaredLength) }
    let total = declaredLength + 8
    guard frame.count >= total else { return WhoopFrameCheck(ok: false, declaredLength: declaredLength) }
    let wantHeaderCRC = whoopCRC16Modbus(Array(frame[0..<6]))
    let gotHeaderCRC = UInt16(frame[6]) | (UInt16(frame[7]) << 8)
    guard wantHeaderCRC == gotHeaderCRC else { return WhoopFrameCheck(ok: false, declaredLength: declaredLength) }
    let payloadStart = 8
    let payloadEnd   = payloadStart + declaredLength - 4
    guard payloadEnd <= frame.count else { return WhoopFrameCheck(ok: false, declaredLength: declaredLength) }
    let payload = Array(frame[payloadStart..<payloadEnd])
    let stored = UInt32(frame[payloadEnd]) | (UInt32(frame[payloadEnd+1]) << 8)
        | (UInt32(frame[payloadEnd+2]) << 16) | (UInt32(frame[payloadEnd+3]) << 24)
    return WhoopFrameCheck(ok: whoopCRC32(payload) == stored, declaredLength: declaredLength)
}

func verifyWhoopFrame(_ frame: [UInt8], family: WhoopDeviceFamily) -> WhoopFrameCheck {
    switch family {
    case .whoop4: return verifyWhoopFrame4(frame)
    case .whoop5: return verifyWhoopFrame5(frame)
    }
}

// MARK: - Reassembler

/// Reassembles fragmented BLE notifications into complete, CRC-verified WHOOP frames.
/// Works for both WHOOP 4.0 (CRC8 header) and 5.0 (CRC16-Modbus header) by reading
/// the declared frame length before buffering.
struct WhoopReassembler {
    private var buffer: [UInt8] = []
    let family: WhoopDeviceFamily

    /// Number of bytes currently buffered (waiting for a complete frame).
    var bufferCount: Int { buffer.count }

    /// Declared total byte count of the next frame, if we have enough header bytes to know it.
    var declaredTotal: Int? {
        guard let sofIdx = buffer.firstIndex(of: 0xAA), sofIdx == 0 else { return nil }
        switch family {
        case .whoop4:
            guard buffer.count >= 4 else { return nil }
            let length = Int(buffer[1]) | (Int(buffer[2]) << 8)
            return (length >= 7 && length <= 4096) ? length + 4 : nil
        case .whoop5:
            guard buffer.count >= 4 else { return nil }
            let dl = Int(buffer[2]) | (Int(buffer[3]) << 8)
            return (dl >= 4 && dl <= 4096) ? dl + 8 : nil
        }
    }

    init(family: WhoopDeviceFamily) {
        self.family = family
    }

    /// Feed a raw BLE notification chunk; returns complete verified frames and count of CRC-failed discards.
    mutating func feed(_ chunk: [UInt8]) -> (frames: [[UInt8]], crcFailures: Int) {
        buffer.append(contentsOf: chunk)
        return drain()
    }

    mutating func reset() { buffer.removeAll() }

    private mutating func drain() -> (frames: [[UInt8]], crcFailures: Int) {
        var frames: [[UInt8]] = []
        var crcFailures = 0
        while true {
            guard let (frame, consumed, crcFailed) = nextFrame() else { break }
            buffer.removeFirst(consumed)
            if let f = frame { frames.append(f) }
            if crcFailed { crcFailures += 1 }
        }
        return (frames, crcFailures)
    }

    /// Returns (frame, bytesConsumed, crcFailed) or nil if there are not enough bytes yet.
    /// frame is nil if the candidate was corrupt (bytes consumed and discarded).
    private func nextFrame() -> (frame: [UInt8]?, consumed: Int, crcFailed: Bool)? {
        guard !buffer.isEmpty else { return nil }  // empty buffer — nothing to parse
        guard let sofIdx = buffer.firstIndex(of: 0xAA) else {
            return (nil, buffer.count, false)  // no SOF anywhere — discard everything
        }
        if sofIdx > 0 { return (nil, sofIdx, false) }  // skip bytes before SOF

        switch family {
        case .whoop4:
            guard buffer.count >= 4 else { return nil }
            let length = Int(buffer[1]) | (Int(buffer[2]) << 8)
            guard length >= 7, length <= 4096 else { return (nil, 1, false) }
            let total = length + 4
            guard buffer.count >= total else { return nil }
            let frame = Array(buffer[0..<total])
            let check = verifyWhoopFrame4(frame)
            return (check.ok ? frame : nil, total, !check.ok)

        case .whoop5:
            guard buffer.count >= 4 else { return nil }
            let declaredLength = Int(buffer[2]) | (Int(buffer[3]) << 8)
            guard declaredLength >= 4, declaredLength <= 4096 else { return (nil, 1, false) }
            let total = declaredLength + 8
            guard buffer.count >= total else { return nil }
            let frame = Array(buffer[0..<total])
            let check = verifyWhoopFrame5(frame)
            return (check.ok ? frame : nil, total, !check.ok)
        }
    }
}
