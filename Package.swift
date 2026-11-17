// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EyeRule",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "EyeRule", path: "Sources/EyeRule"),
        .testTarget(name: "EyeRuleTests", dependencies: ["EyeRule"], path: "Tests/EyeRuleTests")
    ]
)
