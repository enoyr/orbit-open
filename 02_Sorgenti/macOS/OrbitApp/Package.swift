// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OrbitApp",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "OrbitApp", targets: ["OrbitApp"])],
    targets: [.executableTarget(name: "OrbitApp")]
)
