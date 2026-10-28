// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "Memmap",
  platforms: [.macOS(.v14)],
  targets: [
    .target(name: "MemmapCore"),
    .executableTarget(name: "Memmap", dependencies: ["MemmapCore"]),
    .testTarget(name: "MemmapCoreTests", dependencies: ["MemmapCore"]),
  ]
)
