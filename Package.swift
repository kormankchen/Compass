// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Compass",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "Compass", targets: ["Compass"]),
        .library(name: "CompassTestSupport", targets: ["CompassTestSupport"]),
    ],
    targets: [
        .target(name: "Compass"),
        .target(
            name: "CompassTestSupport",
            dependencies: ["Compass"]
        ),
        .testTarget(
            name: "CompassTests",
            dependencies: ["Compass", "CompassTestSupport"]
        ),
    ]
)
