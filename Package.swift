// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MateCore",
    platforms: [.iOS("18.0"), .macOS(.v14)],
    products: [.library(name: "MateCore", targets: ["MateCore"])],
    dependencies: [
        .package(url: "https://github.com/21-DOT-DEV/swift-secp256k1", exact: "0.23.2"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", exact: "1.9.0")
    ],
    targets: [
        .target(name: "MateCore", dependencies: [
            .product(name: "libsecp256k1", package: "swift-secp256k1"),
            .product(name: "CryptoSwift", package: "CryptoSwift")
        ], resources: [.copy("Resources/JPKI")]),
        .testTarget(name: "MateCoreTests", dependencies: ["MateCore"], resources: [.copy("Fixtures/JPKI"), .copy("Fixtures/Shop")])
    ]
)
