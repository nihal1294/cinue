// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "CinueFeature",
    platforms: [.iOS(.v17)],
    products: [
        .library(
            name: "CinueFeature",
            targets: ["CinueFeature"]
        ),
    ],
    targets: [
        .target(
            name: "CinueFeature",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "CinueFeatureTests",
            dependencies: ["CinueFeature"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
