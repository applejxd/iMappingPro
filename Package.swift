// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "iMappingPro",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "iMappingProCore",
            targets: ["iMappingProCore"]
        ),
    ],
    targets: [
        .target(
            name: "iMappingProCore",
            path: "iMappingPro",
            exclude: [
                "iMappingPro.xcodeproj",
                "Info.plist",
            ]
        ),
        .testTarget(
            name: "iMappingProTests",
            dependencies: ["iMappingProCore"],
            path: "Tests/iMappingProTests"
        ),
    ]
)
