import Foundation

/// Every addon module calls `AddonLoader.shared.register(_:)` from a
/// file-level stored property initialiser so the call happens before
/// `AcesoApp.init()` runs.
public protocol IOSAddon {
    var id: String { get }
    func activate()
}

public final class AddonLoader {
    public static let shared = AddonLoader()
    private var addons: [IOSAddon] = []

    private init() {}

    public func register(_ addon: IOSAddon) {
        addons.append(addon)
    }

    public func activateAll() {
        addons.forEach { $0.activate() }
    }
}
