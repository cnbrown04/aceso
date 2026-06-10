// swift-tools-version: 5.10
import PackageDescription

// Rename "AddonTemplate" to your addon name throughout.
let package = Package(
    name: "AddonTemplate",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "AddonTemplate", targets: ["AddonTemplate"]),
    ],
    dependencies: [
        // Add external Swift package deps here, e.g.:
        // .package(url: "https://github.com/example/SomePkg", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "AddonTemplate",
            dependencies: []
        ),
    ]
)
