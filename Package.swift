// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Gong",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GongCore", targets: ["GongCore"]),
        .executable(name: "Gong", targets: ["Gong"]),
    ],
    targets: [
        .target(name: "GongCore"),
        .executableTarget(name: "Gong", dependencies: ["GongCore"]),
        .executableTarget(name: "GongIconExport", dependencies: ["GongCore"]),
        .testTarget(name: "GongCoreTests", dependencies: ["GongCore"]),
    ]
)
