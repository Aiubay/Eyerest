// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CameraSpike",
    platforms: [.macOS(.v13)],
    targets: [.executableTarget(name: "CameraSpike", path: "Sources/CameraSpike")]
)
