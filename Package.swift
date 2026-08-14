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
            path: "Sources/RadarCat"),
        // SwiftPM permet `@testable import` d'un target executable des de
        // Swift 5.5 (genera una còpia com a biblioteca només per als tests),
        // per això no cal reestructurar `RadarCat` en biblioteca + executable
        // prim només per poder-lo testejar.
        .testTarget(
            name: "RadarCatTests",
            dependencies: ["RadarCat"])
    ]
)
