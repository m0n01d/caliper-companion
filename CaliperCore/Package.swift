// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CaliperCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "CaliperCore", targets: ["CaliperCore"]),
        .library(name: "CaliperFlow", targets: ["CaliperFlow"]),
    ],
    targets: [
        .target(name: "CaliperCore"),
        .target(name: "CaliperFlow", dependencies: ["CaliperCore"]),
        .testTarget(name: "CaliperCoreTests", dependencies: ["CaliperCore"]),
        .testTarget(name: "CaliperFlowTests", dependencies: ["CaliperFlow", "CaliperCore"]),
    ],
    swiftLanguageModes: [.v6]
)
