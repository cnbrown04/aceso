import SwiftUI

struct HomeView: View {
    @Environment(WhoopBLEClient.self) private var whoop

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                WhoopScoreCard(whoop: whoop)

                if let error = whoop.connectionError {
                    WhoopPairingCard(message: error) { whoop.retry() }
                }

                if whoop.isHistoricalSyncing || whoop.historicalPacketCount > 0 {
                    WhoopSyncDetailCard(
                        isSyncing: whoop.isHistoricalSyncing,
                        packetCount: whoop.historicalPacketCount
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .scrollClipDisabled()
        .acesoScreenBackground()
        .navigationTitle("Aceso")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
            HomeTopFade()
                .allowsHitTesting(false)
        }
    }
}

// MARK: - WhoopScoreCard (adapted from Goose HomeDailyScoreCard)

private struct WhoopScoreCard: View {
    let whoop: WhoopBLEClient

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            WhoopScoreDial(
                value: hrText,
                unit: whoop.liveHR != nil ? "bpm" : nil,
                progress: hrProgress,
                tint: .red,
                title: "Heart Rate",
                systemImage: "heart.fill"
            )
            WhoopScoreDial(
                value: batteryText,
                unit: whoop.batteryPct != nil ? "%" : nil,
                progress: batteryProgress,
                tint: batteryTint,
                title: "Battery",
                systemImage: "battery.75"
            )
            WhoopScoreDial(
                value: connectionShortLabel,
                unit: nil,
                progress: whoop.connectionState == .connected ? 1 : 0,
                tint: connectionTint,
                title: "Status",
                systemImage: "applewatch"
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .cardSurface(tint: .red, prominent: true)
    }

    private var hrText: String {
        whoop.liveHR.map { "\($0)" } ?? "–"
    }

    private var hrProgress: Double {
        guard let bpm = whoop.liveHR else { return 0 }
        return min(max(Double(bpm - 40) / 160, 0), 1)
    }

    private var batteryText: String {
        whoop.batteryPct.map { "\($0)" } ?? "–"
    }

    private var batteryProgress: Double {
        Double(whoop.batteryPct ?? 0) / 100
    }

    private var batteryTint: Color {
        guard let pct = whoop.batteryPct else { return .secondary }
        return pct > 30 ? .green : pct > 15 ? .orange : .red
    }

    private var connectionShortLabel: String {
        switch whoop.connectionState {
        case .connected:  return "On"
        case .connecting: return "…"
        case .scanning:   return "…"
        case .idle:       return "Off"
        }
    }

    private var connectionTint: Color {
        switch whoop.connectionState {
        case .connected:  return .green
        case .connecting: return .orange
        case .scanning:   return .blue
        case .idle:       return .secondary
        }
    }
}

// MARK: - WhoopScoreDial (direct port of Goose HomeScoreDial)

private struct WhoopScoreDial: View {
    let value: String
    let unit: String?
    let progress: Double
    let tint: Color
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 9) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.14), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)

                VStack(spacing: 0) {
                    Text(value)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: value)
                    if let unit {
                        Text(unit)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(6)
            }
            .frame(width: 88, height: 88)

            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - WhoopSyncDetailCard

private struct WhoopSyncDetailCard: View {
    let isSyncing: Bool
    let packetCount: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: isSyncing ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSyncing ? Color(red: 0.18, green: 0.48, blue: 0.95) : .green)
                .frame(width: 32, height: 32)
                .background(
                    (isSyncing ? Color(red: 0.18, green: 0.48, blue: 0.95) : Color.green).opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .symbolEffect(.rotate, isActive: isSyncing)

            VStack(alignment: .leading, spacing: 3) {
                Text(isSyncing ? "Syncing historical data" : "Sync complete")
                    .font(.subheadline.weight(.semibold))
                if packetCount > 0 {
                    Text("\(packetCount) \(packetCount == 1 ? "packet" : "packets")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .cardSurface(tint: isSyncing ? Color(red: 0.18, green: 0.48, blue: 0.95) : .green)
    }
}

// MARK: - WhoopPairingCard

private struct WhoopPairingCard: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 32, height: 32)
                    .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text("Pairing Required")
                    .font(.headline)
            }

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onRetry) {
                Text("Retry")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.orange, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .cardSurface(tint: .orange, prominent: true)
    }
}

// MARK: - HomeTopFade (ported from Goose HomeScoreViews)

private struct HomeTopFade: View {
    var body: some View {
        GeometryReader { proxy in
            LinearGradient(
                stops: [
                    .init(color: AcesoTheme.appBackground, location: 0),
                    .init(color: AcesoTheme.appBackground.opacity(0.96), location: 0.56),
                    .init(color: AcesoTheme.appBackground.opacity(0), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: max(proxy.safeAreaInsets.top + 44, 82))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
        }
    }
}
