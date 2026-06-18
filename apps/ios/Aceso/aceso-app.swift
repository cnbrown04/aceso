import SwiftUI
import UIKit
import WhoopSDK
import RemoteActionsAddon

@main
struct AcesoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var whoopClient = WhoopSDK.makeBLEClient(family: .whoop4)

    init() {
        AcesoTheme.configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(whoopClient)
                .onAppear {
                    AddonLoader.shared.activateAll(whoop: whoopClient)
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        RemoteActionsCoordinator.shared.storeAPNSToken(deviceToken)
    }
}
