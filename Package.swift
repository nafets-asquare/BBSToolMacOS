// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BBSTool",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "BafangProtocol", targets: ["BafangProtocol"]),
    ],
    targets: [
        .target(name: "BafangProtocol"),
        .testTarget(name: "BafangProtocolTests", dependencies: ["BafangProtocol"]),
    ]
)
