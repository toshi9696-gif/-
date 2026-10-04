// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BodyCompCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BodyCompCore", targets: ["BodyCompCore"]),
    ],
    targets: [
        .target(name: "BodyCompCore"),
        .testTarget(name: "BodyCompCoreTests", dependencies: ["BodyCompCore"]),
    ]
)
