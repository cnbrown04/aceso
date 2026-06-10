// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AppleHealthAddon",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "AppleHealthAddon", targets: ["AppleHealthAddon"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AppleHealthAddon",
            dependencies: [],
            // HealthKit is a system framework — no SPM dep needed.
            linkerSettings: [.linkedFramework("HealthKit")]
        ),
    ]
)
