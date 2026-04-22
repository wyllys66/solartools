// swift-tools-version:5.9
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Wyllys Ingersoll

import PackageDescription

let package = Package(
    name: "solartools",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "SolarCore",
            path: "Sources/SolarCore"
        ),
        .executableTarget(
            name: "solarcli",
            dependencies: ["SolarCore"],
            path: "Sources/solarcli"
        ),
        .executableTarget(
            name: "solarbar",
            dependencies: ["SolarCore"],
            path: "Sources/solarbar"
        ),
    ]
)
