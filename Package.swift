// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "TWMac",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "TWMacCore", targets: ["TWMacCore"]),
        .executable(name: "TWMac", targets: ["TWMac"]),
    ],
    targets: [
        .target(name: "TWMacCore"),
        .executableTarget(name: "TWMac", dependencies: ["TWMacCore"]),
        .testTarget(name: "TWMacCoreTests", dependencies: ["TWMacCore"]),
        .testTarget(name: "TWMacTests", dependencies: ["TWMac"]),
    ],
    swiftLanguageModes: [.v5]
)
