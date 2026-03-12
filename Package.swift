// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DevFlow",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "DevFlow",
            path: "Sources/DevFlow",
            exclude: [
                "Info.plist",
                "DevFlow.entitlements",
            ]
        ),
        .testTarget(
            name: "DevFlowTests",
            dependencies: ["DevFlow"],
            path: "Tests/DevFlowTests"
        ),
    ]
)
