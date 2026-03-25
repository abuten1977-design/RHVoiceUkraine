// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UkrainianVoicesApp",
    defaultLocalization: "en",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "UkrainianVoicesExtension", type: .dynamic, targets: ["Extension"])
    ],
    dependencies: [
        .package(path: "./Core")
    ],
    targets: [
        .target(
            name: "Common",
            dependencies: [
                .product(name: "RHVoice", package: "Core")
            ],
            path: "Common_Polish",
            swiftSettings: [.define("MACOS")]
        ),
        .target(
            name: "Extension",
            dependencies: [
                "Common",
                .product(name: "RHVoice", package: "Core")
            ],
            path: "Extension",
            exclude: ["Tests", "Bridge", "Libraries"],
            swiftSettings: [.define("MACOS")]
        )
    ]
)
