// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WhoopSDK",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WhoopProtocol", targets: ["WhoopProtocol"]),
        .library(name: "WhoopBLE", targets: ["WhoopBLE"]),
        .library(name: "WhoopAPI", targets: ["WhoopAPI"]),
        .library(name: "WhoopSDK", targets: ["WhoopSDK"]),
    ],
    targets: [
        .target(
            name: "WhoopProtocol",
            dependencies: []
        ),
        .target(
            name: "WhoopBLE",
            dependencies: ["WhoopProtocol"],
            linkerSettings: [.linkedFramework("CoreBluetooth")]
        ),
        .target(
            name: "WhoopAPI",
            dependencies: []
        ),
        .target(
            name: "WhoopSDK",
            dependencies: ["WhoopProtocol", "WhoopBLE", "WhoopAPI"]
        ),
        .testTarget(
            name: "WhoopProtocolTests",
            dependencies: ["WhoopProtocol"]
        ),
        .testTarget(
            name: "WhoopAPITests",
            dependencies: ["WhoopAPI"]
        ),
    ]
)
