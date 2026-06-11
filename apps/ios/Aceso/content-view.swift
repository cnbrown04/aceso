import SwiftUI

struct ContentView: View {
    @Environment(WhoopBLEClient.self) var whoop

    var body: some View {
        VStack(spacing: 12) {
            Text(whoop.deviceName ?? "Scanning for WHOOP…")
                .font(.headline)
            if let hr = whoop.liveHR {
                Text("\(hr) bpm")
                    .font(.system(size: 48, weight: .bold))
            }
            if let bat = whoop.batteryPct {
                Text("Battery \(bat)%")
                    .foregroundStyle(.secondary)
            }
            if whoop.connectionError != nil {
                PairingInstructionsView { whoop.retry() }
            } else {
                Text(connectionLabel)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var connectionLabel: String {
        switch whoop.connectionState {
        case .idle:       return "Idle"
        case .scanning:   return "Scanning…"
        case .connecting: return "Connecting…"
        case .connected:  return "Connected"
        }
    }
}

private struct PairingInstructionsView: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHOOP Pairing Required")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Your WHOOP isn't accepting connections. To pair it with Aceso:")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Label("Repeatedly tap the top of your WHOOP", systemImage: "hand.tap")
                Label("Wait for the LED to flash", systemImage: "light.beacon.max")
                Label("Tap Retry below", systemImage: "arrow.clockwise")
            }
            .foregroundStyle(.secondary)
            .font(.subheadline)
            Button("Retry", action: onRetry)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

#Preview {
    ContentView()
        .environment(WhoopBLEClient(family: .whoop4))
}
