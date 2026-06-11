import SwiftUI

// MARK: - Types (ported from GooseBLETypes)

enum AcesoSyncToastPhase: String {
    case syncing
    case synced
    case failed
}

struct AcesoSyncToast: Identifiable, Equatable {
    let id = UUID()
    let phase: AcesoSyncToastPhase
    let title: String
    let detail: String
}

// MARK: - SyncToastHost (ported from Goose RootView)

struct SyncToastHost: View {
    @Environment(WhoopBLEClient.self) private var whoop

    var body: some View {
        VStack {
            if let toast = whoop.syncToast {
                SyncStatusToastView(toast: toast)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: whoop.syncToast?.id)
    }
}

// MARK: - SyncStatusToastView (ported from Goose RootView)

private struct SyncStatusToastView: View {
    let toast: AcesoSyncToast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            SyncToastIcon(systemImage: systemImage, tint: tint, isSyncing: toast.phase == .syncing)

            Text(toast.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .fixedSize(horizontal: true, vertical: false)
        .background {
            Capsule(style: .continuous)
                .fill(toastFill)
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(tint, lineWidth: 1.5)
        }
        .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(toast.title)
    }

    private var systemImage: String {
        switch toast.phase {
        case .syncing: "arrow.triangle.2.circlepath"
        case .synced:  "checkmark.circle.fill"
        case .failed:  "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch toast.phase {
        case .syncing: Color(red: 0.18, green: 0.48, blue: 0.95)
        case .synced:  Color(red: 0.20, green: 0.68, blue: 0.27)
        case .failed:  Color(red: 0.95, green: 0.23, blue: 0.18)
        }
    }

    private var toastFill: Color {
        if colorScheme == .dark {
            switch toast.phase {
            case .syncing: Color(red: 0.07, green: 0.16, blue: 0.25)
            case .synced:  Color(red: 0.07, green: 0.20, blue: 0.12)
            case .failed:  Color(red: 0.26, green: 0.10, blue: 0.09)
            }
        } else {
            switch toast.phase {
            case .syncing: Color(red: 0.84, green: 0.91, blue: 1.0)
            case .synced:  Color(red: 0.86, green: 0.96, blue: 0.88)
            case .failed:  Color(red: 1.0,  green: 0.88, blue: 0.86)
            }
        }
    }
}

// MARK: - SyncToastIcon (ported from Goose RootView)

private struct SyncToastIcon: View {
    let systemImage: String
    let tint: Color
    let isSyncing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isSyncing && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                symbol(rotationDegrees: rotationDegrees(for: context.date))
            }
        } else {
            symbol(rotationDegrees: 0)
        }
    }

    private func symbol(rotationDegrees: Double) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .black))
            .frame(width: 18, height: 18)
            .foregroundStyle(tint)
            .rotationEffect(.degrees(isSyncing ? rotationDegrees : 0))
            .transaction { t in
                t.disablesAnimations = true
                t.animation = nil
            }
    }

    private func rotationDegrees(for date: Date) -> Double {
        let duration = 0.95
        let progress = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration) / duration
        return progress * 360
    }
}
