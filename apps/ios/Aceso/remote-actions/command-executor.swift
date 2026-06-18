import Foundation
import WhoopSDK

public struct RemoteCommandExecutor: Sendable {
    public init() {}

    public func execute(
        _ command: RemoteCommand,
        whoop: WhoopBLEClient,
        remoteActionsEnabled: Bool
    ) -> CommandExecutionResult {
        guard remoteActionsEnabled else {
            return .rejected(message: "Remote actions disabled in Settings")
        }
        guard command.expiresAt > Date() else {
            return .failed(code: "expired", message: "Command timed out")
        }
        guard whoop.isBonded else {
            return .failed(code: "not_bonded", message: "WHOOP is not bonded")
        }
        guard whoop.connectionState == .connected else {
            whoop.connect()
            return .failed(code: "not_connected", message: "Strap disconnected")
        }

        switch command.type {
        case "haptic.pattern4":
            let patternName = command.params["pattern"]?.stringValue ?? "alarm"
            let loops = UInt8(command.params["loops"]?.intValue ?? 2)
            guard let pattern = WhoopHapticPattern4(rawValue: patternRawValue(patternName)) else {
                return .failed(code: "invalid_params", message: "Unknown 4.0 haptic pattern")
            }
            guard whoop.runHaptics(pattern: pattern, loops: loops) else {
                return .failed(code: "ble_rejected", message: "Strap rejected haptic command")
            }
            return .completed(message: "Haptic sent")

        case "haptic.preset5":
            let presetName = command.params["preset"]?.stringValue ?? "notify"
            guard let preset = preset5(named: presetName) else {
                return .failed(code: "invalid_params", message: "Unknown 5.0 haptic preset")
            }
            guard whoop.runHaptics(preset: preset) else {
                return .failed(code: "ble_rejected", message: "Strap rejected haptic command")
            }
            return .completed(message: "Haptic sent")

        case "haptic.stop":
            guard whoop.stopHaptics() else {
                return .failed(code: "ble_rejected", message: "Could not stop haptics")
            }
            return .completed(message: "Haptics stopped")

        case "alarm.set":
            guard let iso = command.params["fire_at_iso"]?.stringValue,
                  let date = ISO8601DateFormatter().date(from: iso) else {
                return .failed(code: "invalid_params", message: "Invalid alarm time")
            }
            guard whoop.setAlarm(at: date) else {
                return .failed(code: "ble_rejected", message: "Could not set alarm")
            }
            return .completed(message: "Alarm armed")

        case "alarm.disable":
            guard whoop.disableAlarm() else {
                return .failed(code: "ble_rejected", message: "Could not disable alarm")
            }
            return .completed(message: "Alarm disabled")

        default:
            return .rejected(message: "Unsupported command type")
        }
    }

    private func patternRawValue(_ name: String) -> UInt8 {
        switch name {
        case "alarm": return WhoopHapticPattern4.alarm.rawValue
        default: return WhoopHapticPattern4.alarm.rawValue
        }
    }

    private func preset5(named name: String) -> WhoopHapticPreset5? {
        switch name {
        case "notify": return .notify
        case "alarm": return .alarm
        case "strong": return .strong
        case "gentle": return .gentle
        default: return nil
        }
    }
}
