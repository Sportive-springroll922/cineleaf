// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CineleafCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CineleafCore", targets: ["CineleafCore"])
    ],
    targets: [
        .target(name: "CineleafCore"),
        .testTarget(name: "CineleafCoreTests", dependencies: ["CineleafCore"])
    ]
)

