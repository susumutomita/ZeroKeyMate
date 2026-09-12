// swift-tools-version: 5.10
import PackageDescription
import Foundation
let native = FileManager.default.fileExists(atPath:
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Runtime/MateAge.xcframework").path)
var targets: [Target] = [.target(name: "MateAgeProof", dependencies: native ? [.target(name: "MateAgeRuntime")] : [])]
if native { targets.append(.binaryTarget(name: "MateAgeRuntime", path: "Runtime/MateAge.xcframework")) }
let package = Package(name: "MateAgeProof", platforms: [.iOS(.v17)],
    products: [.library(name: "MateAgeProof", targets: ["MateAgeProof"])], targets: targets)
