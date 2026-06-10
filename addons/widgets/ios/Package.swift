// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WidgetsAddon",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "WidgetsAddon", targets: ["WidgetsAddon"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "WidgetsAddon",
            dependencies: [],
            linkerSettings: [.linkedFramework("WidgetKit")]
        ),
    ]
)
