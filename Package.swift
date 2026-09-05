// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MateCore",
    platforms: [.iOS("18.0"), .macOS(.v14)],
    products: [.library(name: "MateCore", targets: ["MateCore"])],
    targets: [
        .target(name: "MateCore"),
        .testTarget(name: "MateCoreTests", dependencies: ["MateCore"])
    ]
)
