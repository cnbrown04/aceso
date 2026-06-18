import Foundation

public enum WhoopScoreState: String, Codable, Sendable {
    case scored = "SCORED"
    case pendingScore = "PENDING_SCORE"
    case unscorable = "UNSCORABLE"
}

public struct WhoopUserProfile: Codable, Sendable, Equatable {
    public let userId: Int
    public let email: String
    public let firstName: String
    public let lastName: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case email
        case firstName = "first_name"
        case lastName = "last_name"
    }
}

public struct WhoopBodyMeasurement: Codable, Sendable, Equatable {
    public let heightMeter: Double
    public let weightKilogram: Double
    public let maxHeartRate: Int

    enum CodingKeys: String, CodingKey {
        case heightMeter = "height_meter"
        case weightKilogram = "weight_kilogram"
        case maxHeartRate = "max_heart_rate"
    }
}

public struct WhoopCycleScore: Codable, Sendable, Equatable {
    public let strain: Double
    public let kilojoule: Double
    public let averageHeartRate: Int
    public let maxHeartRate: Int

    enum CodingKeys: String, CodingKey {
        case strain, kilojoule
        case averageHeartRate = "average_heart_rate"
        case maxHeartRate = "max_heart_rate"
    }
}

public struct WhoopCycle: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let userId: Int
    public let createdAt: Date
    public let updatedAt: Date
    public let start: Date
    public let end: Date?
    public let timezoneOffset: String
    public let scoreState: WhoopScoreState
    public let score: WhoopCycleScore?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case start, end
        case timezoneOffset = "timezone_offset"
        case scoreState = "score_state"
        case score
    }
}

public struct WhoopSleepStageSummary: Codable, Sendable, Equatable {
    public let totalInBedTimeMilli: Int
    public let totalAwakeTimeMilli: Int
    public let totalNoDataTimeMilli: Int
    public let totalLightSleepTimeMilli: Int
    public let totalSlowWaveSleepTimeMilli: Int
    public let totalRemSleepTimeMilli: Int
    public let sleepCycleCount: Int
    public let disturbanceCount: Int

    enum CodingKeys: String, CodingKey {
        case totalInBedTimeMilli = "total_in_bed_time_milli"
        case totalAwakeTimeMilli = "total_awake_time_milli"
        case totalNoDataTimeMilli = "total_no_data_time_milli"
        case totalLightSleepTimeMilli = "total_light_sleep_time_milli"
        case totalSlowWaveSleepTimeMilli = "total_slow_wave_sleep_time_milli"
        case totalRemSleepTimeMilli = "total_rem_sleep_time_milli"
        case sleepCycleCount = "sleep_cycle_count"
        case disturbanceCount = "disturbance_count"
    }
}

public struct WhoopSleepNeeded: Codable, Sendable, Equatable {
    public let baselineMilli: Int
    public let needFromSleepDebtMilli: Int
    public let needFromRecentStrainMilli: Int
    public let needFromRecentNapMilli: Int

    enum CodingKeys: String, CodingKey {
        case baselineMilli = "baseline_milli"
        case needFromSleepDebtMilli = "need_from_sleep_debt_milli"
        case needFromRecentStrainMilli = "need_from_recent_strain_milli"
        case needFromRecentNapMilli = "need_from_recent_nap_milli"
    }
}

public struct WhoopSleepScore: Codable, Sendable, Equatable {
    public let stageSummary: WhoopSleepStageSummary
    public let sleepNeeded: WhoopSleepNeeded
    public let respiratoryRate: Double?
    public let sleepPerformancePercentage: Double?
    public let sleepConsistencyPercentage: Double?
    public let sleepEfficiencyPercentage: Double?

    enum CodingKeys: String, CodingKey {
        case stageSummary = "stage_summary"
        case sleepNeeded = "sleep_needed"
        case respiratoryRate = "respiratory_rate"
        case sleepPerformancePercentage = "sleep_performance_percentage"
        case sleepConsistencyPercentage = "sleep_consistency_percentage"
        case sleepEfficiencyPercentage = "sleep_efficiency_percentage"
    }
}

public struct WhoopSleep: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let v1Id: Int?
    public let userId: Int
    public let createdAt: Date
    public let updatedAt: Date
    public let start: Date
    public let end: Date
    public let timezoneOffset: String
    public let nap: Bool
    public let scoreState: WhoopScoreState
    public let score: WhoopSleepScore?

    enum CodingKeys: String, CodingKey {
        case id
        case v1Id = "v1_id"
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case start, end
        case timezoneOffset = "timezone_offset"
        case nap
        case scoreState = "score_state"
        case score
    }
}

public struct WhoopRecoveryScore: Codable, Sendable, Equatable {
    public let userCalibrating: Bool
    public let recoveryScore: Double
    public let restingHeartRate: Double
    public let hrvRmssdMilli: Double
    public let spo2Percentage: Double?
    public let skinTempCelsius: Double?

    enum CodingKeys: String, CodingKey {
        case userCalibrating = "user_calibrating"
        case recoveryScore = "recovery_score"
        case restingHeartRate = "resting_heart_rate"
        case hrvRmssdMilli = "hrv_rmssd_milli"
        case spo2Percentage = "spo2_percentage"
        case skinTempCelsius = "skin_temp_celsius"
    }
}

public struct WhoopRecovery: Codable, Sendable, Equatable {
    public let cycleId: Int
    public let sleepId: UUID
    public let userId: Int
    public let createdAt: Date
    public let updatedAt: Date
    public let scoreState: WhoopScoreState
    public let score: WhoopRecoveryScore?

    enum CodingKeys: String, CodingKey {
        case cycleId = "cycle_id"
        case sleepId = "sleep_id"
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case scoreState = "score_state"
        case score
    }
}

public struct WhoopZoneDurations: Codable, Sendable, Equatable {
    public let zoneZeroMilli: Int
    public let zoneOneMilli: Int
    public let zoneTwoMilli: Int
    public let zoneThreeMilli: Int
    public let zoneFourMilli: Int
    public let zoneFiveMilli: Int

    enum CodingKeys: String, CodingKey {
        case zoneZeroMilli = "zone_zero_milli"
        case zoneOneMilli = "zone_one_milli"
        case zoneTwoMilli = "zone_two_milli"
        case zoneThreeMilli = "zone_three_milli"
        case zoneFourMilli = "zone_four_milli"
        case zoneFiveMilli = "zone_five_milli"
    }
}

public struct WhoopWorkoutScore: Codable, Sendable, Equatable {
    public let strain: Double
    public let averageHeartRate: Int
    public let maxHeartRate: Int
    public let kilojoule: Double
    public let percentRecorded: Double
    public let distanceMeter: Double?
    public let altitudeGainMeter: Double?
    public let altitudeChangeMeter: Double?
    public let zoneDurations: WhoopZoneDurations

    enum CodingKeys: String, CodingKey {
        case strain
        case averageHeartRate = "average_heart_rate"
        case maxHeartRate = "max_heart_rate"
        case kilojoule
        case percentRecorded = "percent_recorded"
        case distanceMeter = "distance_meter"
        case altitudeGainMeter = "altitude_gain_meter"
        case altitudeChangeMeter = "altitude_change_meter"
        case zoneDurations = "zone_durations"
    }
}

public struct WhoopWorkout: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let v1Id: Int?
    public let sportId: Int?
    public let userId: Int
    public let createdAt: Date
    public let updatedAt: Date
    public let start: Date
    public let end: Date
    public let timezoneOffset: String
    public let sportName: String
    public let scoreState: WhoopScoreState
    public let score: WhoopWorkoutScore?

    enum CodingKeys: String, CodingKey {
        case id
        case v1Id = "v1_id"
        case sportId = "sport_id"
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case start, end
        case timezoneOffset = "timezone_offset"
        case sportName = "sport_name"
        case scoreState = "score_state"
        case score
    }
}

public struct WhoopPaginatedResponse<T: Codable & Sendable>: Codable, Sendable {
    public let records: [T]
    public let nextToken: String?

    enum CodingKeys: String, CodingKey {
        case records
        case nextToken = "next_token"
    }

    public var hasMore: Bool { nextToken != nil }
}

public typealias WhoopPaginatedCycles = WhoopPaginatedResponse<WhoopCycle>
public typealias WhoopPaginatedSleeps = WhoopPaginatedResponse<WhoopSleep>
public typealias WhoopPaginatedRecoveries = WhoopPaginatedResponse<WhoopRecovery>
public typealias WhoopPaginatedWorkouts = WhoopPaginatedResponse<WhoopWorkout>

public struct WhoopActivityMapping: Codable, Sendable, Equatable {
    public let v2ActivityId: UUID

    enum CodingKeys: String, CodingKey {
        case v2ActivityId = "v2_activity_id"
    }
}
