import Foundation

/// Decodes raw IMU and optical sensor arrays from REALTIME_RAW_DATA packets.
///
/// Layout confirmed by johnmiddleton12/my-whoop controlled-motion analysis.
public enum WhoopRawDecoder {
    public static let imuPacketDataLength = 1917
    public static let opticalPacketDataLength = 1921
    public static let samplesPerAxis = 100

    private static let accelXOffset = 82
    private static let accelYOffset = 282
    private static let accelZOffset = 482
    private static let gyroXOffset = 685
    private static let gyroYOffset = 885
    private static let gyroZOffset = 1085

    public static func decodeIMUPacket(_ frame: [UInt8], family: WhoopDeviceFamily = .whoop4) -> WhoopIMUSample? {
        let data = frameData(frame, family: family)
        guard data.count >= gyroZOffset + 2 else { return nil }

        let ts = Int(readU32LE(data, 4) ?? 0)
        let hr = Int(data[14])

        let ax = readI16LE(data, accelXOffset) ?? 0
        let ay = readI16LE(data, accelYOffset) ?? 0
        let az = readI16LE(data, accelZOffset) ?? 0
        let gx = readI16LE(data, gyroXOffset) ?? 0
        let gy = readI16LE(data, gyroYOffset) ?? 0
        let gz = readI16LE(data, gyroZOffset) ?? 0

        _ = hr
        return WhoopIMUSample(ts: ts, accelX: ax, accelY: ay, accelZ: az, gyroX: gx, gyroY: gy, gyroZ: gz)
    }

    public static func decodeAllIMUSamples(_ frame: [UInt8], family: WhoopDeviceFamily = .whoop4) -> [WhoopIMUSample] {
        let data = frameData(frame, family: family)
        guard data.count >= gyroZOffset + samplesPerAxis * 2 else { return [] }

        let baseTs = Int(readU32LE(data, 4) ?? 0)
        var samples: [WhoopIMUSample] = []
        samples.reserveCapacity(samplesPerAxis)

        for i in 0..<samplesPerAxis {
            let off = i * 2
            let ax = readI16LE(data, accelXOffset + off) ?? 0
            let ay = readI16LE(data, accelYOffset + off) ?? 0
            let az = readI16LE(data, accelZOffset + off) ?? 0
            let gx = readI16LE(data, gyroXOffset + off) ?? 0
            let gy = readI16LE(data, gyroYOffset + off) ?? 0
            let gz = readI16LE(data, gyroZOffset + off) ?? 0
            samples.append(WhoopIMUSample(
                ts: baseTs + i, accelX: ax, accelY: ay, accelZ: az,
                gyroX: gx, gyroY: gy, gyroZ: gz
            ))
        }
        return samples
    }

    public static func decodeOpticalPacket(_ frame: [UInt8], family: WhoopDeviceFamily = .whoop4) -> WhoopRawOpticalPacket? {
        let data = frameData(frame, family: family)
        guard data.count >= 40 else { return nil }

        let ts = Int(readU32LE(data, 4) ?? 0)
        let hr = Int(data[14])
        var samples: [UInt32] = []
        var offset = 33
        while offset + 2 < data.count {
            let sample = UInt32(data[offset])
                | (UInt32(data[offset + 1]) << 8)
                | (UInt32(data[offset + 2]) << 16)
            samples.append(sample)
            offset += 3
        }
        return WhoopRawOpticalPacket(ts: ts, heartRate: hr, samples: samples)
    }

    public static func decodeVariableIMUPacket(_ frame: [UInt8], family: WhoopDeviceFamily = .whoop4) -> WhoopIMUSample? {
        let data = frameData(frame, family: family)
        guard data.count >= 28 else { return nil }
        let ts = Int(readU32LE(data, 4) ?? 0)
        let gCount = Int(readU16LE(data, 24) ?? 0)
        let hCount = Int(readU16LE(data, 26) ?? 0)
        let headerSize = 28
        let accelStart = headerSize
        let gyroStart = accelStart + gCount * 2
        guard gyroStart + 10 < data.count else { return nil }
        _ = hCount
        return WhoopIMUSample(
            ts: ts,
            accelX: readI16LE(data, accelStart) ?? 0,
            accelY: readI16LE(data, accelStart + 2) ?? 0,
            accelZ: readI16LE(data, accelStart + 4) ?? 0,
            gyroX: readI16LE(data, gyroStart) ?? 0,
            gyroY: readI16LE(data, gyroStart + 2) ?? 0,
            gyroZ: readI16LE(data, gyroStart + 4) ?? 0
        )
    }

    private static func frameData(_ frame: [UInt8], family: WhoopDeviceFamily) -> [UInt8] {
        let base = family == .whoop5 ? 11 : 7
        guard frame.count > base + 4 else { return [] }
        let end = frame.count - 4
        return Array(frame[base..<end])
    }

    private static func readU16LE(_ bytes: [UInt8], _ offset: Int) -> UInt16? {
        guard offset + 1 < bytes.count else { return nil }
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readU32LE(_ bytes: [UInt8], _ offset: Int) -> UInt32? {
        guard offset + 3 < bytes.count else { return nil }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func readI16LE(_ bytes: [UInt8], _ offset: Int) -> Int16? {
        guard let raw = readU16LE(bytes, offset) else { return nil }
        return Int16(bitPattern: raw)
    }
}
