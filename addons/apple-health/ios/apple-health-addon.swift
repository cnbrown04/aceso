import HealthKit

struct AppleHealthAddon: IOSAddon {
    let id = "com.aceso.addon.apple-health"
    private let store = HKHealthStore()

    func activate() {
        // request HealthKit authorisation and begin writing metrics
    }
}
