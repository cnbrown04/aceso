import Foundation
import RemoteActionsAddon
import WhoopSDK

struct RemoteActionsAddonBridge: IOSAddonWithWhoop {
    let id = "remote-actions"

    func activate() {}

    func activate(whoop: WhoopBLEClient, serverURL: URL?) {
        if let serverURL {
            RemoteActionsCoordinator.shared.setServerURL(serverURL)
        }
        RemoteActionsCoordinator.shared.activate(whoop: whoop)
    }
}

private let _registerRemoteActions: Void = {
    AddonLoader.shared.register(RemoteActionsAddonBridge())
}()
