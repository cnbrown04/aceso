import SwiftUI
import WhoopSDK

struct DeviceView: View {
    @Environment(WhoopBLEClient.self) private var whoop

    var body: some View {
        List {
            Section("Status") {
                LabeledContent("Connection", value: connectionLabel)
                if let name = whoop.deviceName {
                    LabeledContent("Device", value: name)
                }
                LabeledContent("Heart Rate", value: hrLabel)
                LabeledContent("Battery", value: batteryLabel)
                if whoop.historicalPacketCount > 0 || whoop.isHistoricalSyncing {
                    LabeledContent("Historical Sync", value: historicalSyncLabel)
                }
                if let error = whoop.connectionError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Actions") {
                switch whoop.connectionState {
                case .idle:
                    Button("Connect") { whoop.connect() }
                case .scanning, .connecting:
                    Button("Connecting…") {}.disabled(true)
                case .connected:
                    Button("Disconnect", role: .destructive) { whoop.disconnect() }
                }

                if whoop.connectionError != nil {
                    Button("Retry") { whoop.retry() }
                }
            }

            Section("Testing") {
                Button("Re-sync Historical Data") {
                    whoop.resyncHistoricalData()
                }
                .disabled(whoop.connectionState != .connected || whoop.isHistoricalSyncing)
            }
        }
        .acesoListBackground()
        .navigationTitle("Device")
    }

    private var connectionLabel: String {
        switch whoop.connectionState {
        case .idle:       "Idle"
        case .scanning:   "Scanning…"
        case .connecting: "Connecting…"
        case .connected:  "Connected"
        }
    }

    private var hrLabel: String {
        guard let bpm = whoop.liveHR else { return "–" }
        return "\(bpm) bpm"
    }

    private var batteryLabel: String {
        guard let pct = whoop.batteryPct else { return "–" }
        return "\(pct)%"
    }

    private var historicalSyncLabel: String {
        let count = whoop.historicalPacketCount
        if whoop.isHistoricalSyncing {
            return count == 0 ? "Syncing…" : "Syncing… (\(count) packets)"
        }
        return "\(count) \(count == 1 ? "packet" : "packets")"
    }
}
