import SwiftUI

struct AppShellView: View {
  var body: some View {
    TabView {
      ForEach(AcesoTab.allCases) { tab in
        NavigationStack {
          tabContent(for: tab)
        }
        .tabItem {
          Label(tab.title, systemImage: tab.systemImage)
        }
        .tag(tab)
      }
    }
  }

  @ViewBuilder
  private func tabContent(for tab: AcesoTab) -> some View {
    switch tab {
    case .home:   HomeView()
    case .device: DeviceView()
    }
  }
}

enum AcesoTab: String, CaseIterable, Identifiable {
  case home
  case device

  var id: String { rawValue }

  var title: String {
    switch self {
    case .home:   "Home"
    case .device: "Device"
    }
  }

  var systemImage: String {
    switch self {
    case .home:   "heart.fill"
    case .device: "applewatch"
    }
  }
}
