// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Swivel",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Swivel", targets: ["Swivel"]),
        .library(name: "SwivelCore", targets: ["SwivelCore"]),
    ],
    targets: [
        .target(name: "SwivelCore"),
        .executableTarget(name: "Swivel", dependencies: ["SwivelCore"]),
        .testTarget(name: "SwivelCoreTests", dependencies: ["SwivelCore"]),
    ]
)
