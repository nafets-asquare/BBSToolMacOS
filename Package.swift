// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BBSTool",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BafangProtocol", targets: ["BafangProtocol"]),
        .library(name: "BafangSerial", targets: ["BafangSerial"]),
        .executable(name: "bbstool", targets: ["bbstool"]),
        .executable(name: "BBSToolApp", targets: ["BBSToolApp"]),
    ],
    targets: [
        .target(name: "BafangProtocol"),
        .target(name: "BafangSerial", dependencies: ["BafangProtocol"]),
        .executableTarget(name: "bbstool", dependencies: ["BafangProtocol", "BafangSerial"]),
        .executableTarget(name: "BBSToolApp", dependencies: ["BafangProtocol", "BafangSerial"]),
        .testTarget(name: "BafangProtocolTests", dependencies: ["BafangProtocol"]),
        .testTarget(name: "BafangSerialTests", dependencies: ["BafangSerial"]),
        .testTarget(name: "BBSToolAppTests", dependencies: ["BBSToolApp"]),
    ]
)
