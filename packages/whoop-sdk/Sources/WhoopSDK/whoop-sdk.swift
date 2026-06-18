import Foundation
@_exported import WhoopAPI
@_exported import WhoopBLE
@_exported import WhoopProtocol

/// Unified entry point for WHOOP strap BLE and cloud REST API access.
public enum WhoopSDK {
    public static let sdkVersion = "1.0.0"

    /// Create a BLE client for direct strap communication (WHOOP 4.0 or 5.0).
    public static func makeBLEClient(family: WhoopDeviceFamily = .whoop4) -> WhoopBLEClient {
        WhoopBLEClient(family: family)
    }

    /// Create a BLE client by auto-detecting strap generation from a service UUID.
    public static func makeBLEClient(detectedServiceUUID: String) -> WhoopBLEClient? {
        guard let family = WhoopDeviceFamily.from(serviceUUID: detectedServiceUUID) else { return nil }
        return WhoopBLEClient(family: family)
    }

    /// Create a REST API client for WHOOP cloud data (cycles, sleep, recovery, workouts).
    public static func makeAPIClient(
        token: WhoopOAuthToken,
        clientID: String? = nil,
        clientSecret: String? = nil
    ) -> WhoopAPIClient {
        WhoopAPIClient(token: token, clientID: clientID, clientSecret: clientSecret)
    }
}
