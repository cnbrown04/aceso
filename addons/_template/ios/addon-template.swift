import Foundation
// import Aceso  ← uncomment once the main app target is a local package dep

// Replace "Template" with your addon name throughout.
struct TemplateAddon: IOSAddon {
    let id = "com.aceso.addon.template"

    func activate() {
        // wire up your addon here
    }
}

// Module initialiser — runs before AppDelegate.
// private let _register: Void = {
//     AddonLoader.shared.register(TemplateAddon())
// }()
