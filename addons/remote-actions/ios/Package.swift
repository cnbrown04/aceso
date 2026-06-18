// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RemoteActionsAddon",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "RemoteActionsAddon", targets: ["RemoteActionsAddon"]),
    ],
    dependencies: [
        .package(path: "../../../packages/whoop-sdk"),
    ],
    targets: [
        .target(
            name: "RemoteActionsAddon",
            dependencies: [
                .product(name: "WhoopSDK", package: "whoop-sdk"),
            ],
            linkerSettings: [
                .linkedFramework("UserNotifications"),
            ]
        ),
        .testTarget(
            name: "RemoteActionsAddonTests",
            dependencies: ["RemoteActionsAddon"]
        ),
    ]
)
