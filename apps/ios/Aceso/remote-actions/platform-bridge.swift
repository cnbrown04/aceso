import Foundation

#if canImport(UIKit)
import UIKit
#endif

public enum UIDeviceBridge {
    public static var identifier: String {
        #if canImport(UIKit)
        return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        return UUID().uuidString
        #endif
    }

    public static var name: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "iOS Device"
        #endif
    }
}

public enum UIApplicationBridge {
    public static func registerForRemoteNotifications() {
        #if canImport(UIKit)
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }
}
