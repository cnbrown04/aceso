import WidgetKit

struct WidgetAddon: IOSAddon {
    let id = "com.aceso.addon.widgets"

    func activate() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
