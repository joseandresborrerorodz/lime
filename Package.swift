// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Lime",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Lime", targets: ["Lime"]),
        .library(name: "LimeCore", targets: ["LimeCore"]),
    ],
    targets: [
        .target(name: "LimeCore"),
        .executableTarget(name: "Lime", dependencies: ["LimeCore"]),
        .testTarget(name: "LimeCoreTests", dependencies: ["LimeCore"]),
    ]
)
