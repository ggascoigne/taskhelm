// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "TaskHelm",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "TaskHelmCore", targets: ["TaskHelmCore"]),
        .executable(name: "TaskHelm", targets: ["TaskHelm"]),
    ],
    targets: [
        .target(name: "TaskHelmCore"),
        .executableTarget(name: "TaskHelm", dependencies: ["TaskHelmCore"]),
        .testTarget(name: "TaskHelmCoreTests", dependencies: ["TaskHelmCore"]),
        .testTarget(name: "TaskHelmTests", dependencies: ["TaskHelm"]),
    ],
    swiftLanguageModes: [.v5]
)
