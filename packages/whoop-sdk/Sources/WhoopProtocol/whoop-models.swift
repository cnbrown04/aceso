import Foundation

public struct WhoopHRSample: Codable, Sendable, Equatable {
    public let ts: Int
    public let bpm: Int

    public init(ts: Int, bpm: Int) {
        self.ts = ts
        self.bpm = bpm
    }
}

public struct WhoopRRInterval: Codable, Sendable, Equatable {
    public let ts: Int
    public let rrMs: Int

    enum CodingKeys: String, CodingKey {
        case ts
        case rrMs = "rr_ms"
    }

    public init(ts: Int, rrMs: Int) {
        self.ts = ts
        self.rrMs = rrMs
    }
}

public struct WhoopBatterySample: Codable, Sendable, Equatable {
    public let ts: Int
    public let pct: Double

    public init(ts: Int, pct: Double) {
        self.ts = ts
        self.pct = pct
    }
}

public struct WhoopIMUSample: Codable, Sendable, Equatable {
    public let ts: Int
    public let accelX: Int16
    public let accelY: Int16
    public let accelZ: Int16
    public let gyroX: Int16
    public let gyroY: Int16
    public let gyroZ: Int16

    public init(ts: Int, accelX: Int16, accelY: Int16, accelZ: Int16,
                gyroX: Int16, gyroY: Int16, gyroZ: Int16) {
        self.ts = ts
        self.accelX = accelX
        self.accelY = accelY
        self.accelZ = accelZ
        self.gyroX = gyroX
        self.gyroY = gyroY
        self.gyroZ = gyroZ
    }
}

public struct WhoopRawOpticalPacket: Codable, Sendable, Equatable {
    public let ts: Int
    public let heartRate: Int
    public let samples: [UInt32]

    public init(ts: Int, heartRate: Int, samples: [UInt32]) {
        self.ts = ts
        self.heartRate = heartRate
        self.samples = samples
    }
}

public struct WhoopStrapEvent: Codable, Sendable, Equatable {
    public let event: WhoopEventNumber
    public let ts: Int
    public let batteryPct: Double?
    public let batteryMv: Int?

    public init(event: WhoopEventNumber, ts: Int, batteryPct: Double? = nil, batteryMv: Int? = nil) {
        self.event = event
        self.ts = ts
        self.batteryPct = batteryPct
        self.batteryMv = batteryMv
    }
}

public struct WhoopVersionInfo: Codable, Sendable, Equatable {
    public let harvard: String
    public let boylston: String

    public init(harvard: String, boylston: String) {
        self.harvard = harvard
        self.boylston = boylston
    }
}

public struct WhoopDataRange: Codable, Sendable, Equatable {
    public let oldestUnix: Int
    public let newestUnix: Int

    public init(oldestUnix: Int, newestUnix: Int) {
        self.oldestUnix = oldestUnix
        self.newestUnix = newestUnix
    }
}

/// Armed alarm time returned by `GET_ALARM_TIME` (opcode 67).
public struct WhoopAlarmTime: Codable, Sendable, Equatable {
    public let epochSec: UInt32

    public init(epochSec: UInt32) {
        self.epochSec = epochSec
    }

    public var date: Date { Date(timeIntervalSince1970: TimeInterval(epochSec)) }
}

public struct WhoopExtendedBattery: Codable, Sendable, Equatable {
    public let pct: Double
    public let millivolts: Int

    public init(pct: Double, millivolts: Int) {
        self.pct = pct
        self.millivolts = millivolts
    }
}

public struct WhoopSampleBatch: Codable, Sendable {
    public let deviceID: String
    public var hrSamples: [WhoopHRSample]
    public var rrIntervals: [WhoopRRInterval]
    public var batterySamples: [WhoopBatterySample]
    public var imuSamples: [WhoopIMUSample]
    public var opticalPackets: [WhoopRawOpticalPacket]
    public var events: [WhoopStrapEvent]

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case hrSamples = "hr_samples"
        case rrIntervals = "rr_intervals"
        case batterySamples = "battery_samples"
        case imuSamples = "imu_samples"
        case opticalPackets = "optical_packets"
        case events
    }

    public init(
        deviceID: String,
        hrSamples: [WhoopHRSample] = [],
        rrIntervals: [WhoopRRInterval] = [],
        batterySamples: [WhoopBatterySample] = [],
        imuSamples: [WhoopIMUSample] = [],
        opticalPackets: [WhoopRawOpticalPacket] = [],
        events: [WhoopStrapEvent] = []
    ) {
        self.deviceID = deviceID
        self.hrSamples = hrSamples
        self.rrIntervals = rrIntervals
        self.batterySamples = batterySamples
        self.imuSamples = imuSamples
        self.opticalPackets = opticalPackets
        self.events = events
    }

    public var isEmpty: Bool {
        hrSamples.isEmpty && rrIntervals.isEmpty && batterySamples.isEmpty
            && imuSamples.isEmpty && opticalPackets.isEmpty && events.isEmpty
    }
}

public enum StandardHeartRate {
    public static func parse(_ data: [UInt8]) -> (hr: Int, rr: [Int])? {
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
        if flags & 0x08 != 0 { idx += 2 }
        var rr: [Int] = []
        if (flags >> 4) & 0x01 != 0 {
            while idx + 1 < data.count {
                let raw = Int(data[idx]) | (Int(data[idx + 1]) << 8)
                rr.append(Int((Double(raw) / 1024.0 * 1000.0).rounded()))
                idx += 2
            }
        }
        return (hr, rr)
    }
}
