// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MOUSE",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MOUSE", targets: ["MOUSE"]),
        .library(name: "ScrollCore", targets: ["ScrollCore"])
    ],
    targets: [
        .target(name: "ScrollCore"),
        .executableTarget(name: "MOUSE", dependencies: ["ScrollCore"]),
        .testTarget(name: "ScrollCoreTests", dependencies: ["ScrollCore"])
    ]
)
