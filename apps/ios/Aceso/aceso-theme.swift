import SwiftUI
import UIKit

enum AcesoTheme {
  static let appBackground = Color(uiColor: appBackgroundUIColor)
  static let plainBackground = Color(uiColor: plainBackgroundUIColor)

  static func configureAppearance() {
    UIWindow.appearance().backgroundColor = appBackgroundUIColor
    UITableView.appearance().backgroundColor = appBackgroundUIColor
    UICollectionView.appearance().backgroundColor = appBackgroundUIColor

    let navAppearance = UINavigationBarAppearance()
    navAppearance.configureWithTransparentBackground()
    navAppearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
    navAppearance.backgroundColor = navigationBarBackgroundUIColor
    navAppearance.shadowColor = .clear
    UINavigationBar.appearance().standardAppearance = navAppearance
    UINavigationBar.appearance().compactAppearance = navAppearance
    UINavigationBar.appearance().scrollEdgeAppearance = navAppearance

    let tabAppearance = UITabBarAppearance()
    tabAppearance.configureWithOpaqueBackground()
    tabAppearance.backgroundColor = appBackgroundUIColor
    tabAppearance.shadowColor = .clear
    UITabBar.appearance().standardAppearance = tabAppearance
    UITabBar.appearance().scrollEdgeAppearance = tabAppearance
  }

  private static let deviceBackgroundUIColor = UIColor(red: 0.06, green: 0.09, blue: 0.11, alpha: 1)

  static let appBackgroundUIColor = UIColor { traits in
    traits.userInterfaceStyle == .dark ? deviceBackgroundUIColor : .systemGroupedBackground
  }

  private static let plainBackgroundUIColor = UIColor { traits in
    traits.userInterfaceStyle == .dark ? deviceBackgroundUIColor : .systemBackground
  }

  private static let navigationBarBackgroundUIColor = UIColor { traits in
    let alpha: CGFloat = traits.userInterfaceStyle == .dark ? 0.58 : 0.46
    return appBackgroundUIColor.resolvedColor(with: traits).withAlphaComponent(alpha)
  }
}

extension View {
  func acesoScreenBackground() -> some View {
    background(AcesoTheme.appBackground.ignoresSafeArea())
  }

  func acesoListBackground() -> some View {
    scrollContentBackground(.hidden)
      .background(AcesoTheme.appBackground.ignoresSafeArea())
  }

  func cardSurface(tint: Color = .blue, prominent: Bool = false) -> some View {
    modifier(CardSurfaceModifier(tint: tint, prominent: prominent))
  }
}

struct CardSurfaceModifier: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme
  let tint: Color
  let prominent: Bool

  func body(content: Content) -> some View {
    content
      .background {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(baseFill)
          .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
              .fill(
                LinearGradient(
                  colors: [
                    tint.opacity(tintOpacity),
                    tint.opacity(tintOpacity * 0.36),
                    .clear,
                  ],
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                )
              )
          }
      }
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .strokeBorder(tint.opacity(borderOpacity), lineWidth: 1)
      }
      .shadow(color: shadowColor, radius: prominent ? 5 : 2, x: 0, y: prominent ? 3 : 1)
  }

  private var baseFill: Color {
    colorScheme == .dark
      ? Color.white.opacity(prominent ? 0.070 : 0.055)
      : Color(UIColor.secondarySystemGroupedBackground)
  }

  private var tintOpacity: Double {
    colorScheme == .dark
      ? (prominent ? 0.085 : 0.055)
      : (prominent ? 0.040 : 0.024)
  }

  private var borderOpacity: Double {
    colorScheme == .dark ? 0.14 : 0.075
  }

  private var shadowColor: Color {
    colorScheme == .dark ? .black.opacity(0.10) : .black.opacity(prominent ? 0.026 : 0.014)
  }
}

struct SectionHeader: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.title3.bold())
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 4)
  }
}
