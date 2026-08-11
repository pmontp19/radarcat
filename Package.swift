// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RadarCat",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "RadarCat",
            path: "Sources/RadarCat")
    ]
)
