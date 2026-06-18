import Foundation
import WhoopSDK

/// Every addon module calls `AddonLoader.shared.register(_:)` from a
/// file-level stored property initialiser so the call happens before
/// `AcesoApp.init()` runs.
public protocol IOSAddon {
    var id: String { get }
    func activate()
}

/// Optional hook for addons that need the shared WHOOP BLE client at activation time.
public protocol IOSAddonWithWhoop: IOSAddon {
    func activate(whoop: WhoopBLEClient, serverURL: URL?)
}

public final class AddonLoader {
    public static let shared = AddonLoader()
    private var addons: [IOSAddon] = []

    private init() {}

    public func register(_ addon: IOSAddon) {
        addons.append(addon)
    }

    public func activateAll(whoop: WhoopBLEClient? = nil, serverURL: URL? = nil) {
        addons.forEach { addon in
            if let whoop, let withWhoop = addon as? IOSAddonWithWhoop {
                withWhoop.activate(whoop: whoop, serverURL: serverURL)
            } else {
                addon.activate()
            }
        }
    }
}
