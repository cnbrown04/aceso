import SwiftUI

@main
struct AcesoApp: App {
    @State private var whoopClient = WhoopBLEClient(family: .whoop4)

    init() {
        AcesoTheme.configureAppearance()
        AddonLoader.shared.activateAll()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(whoopClient)
        }
    }
}
