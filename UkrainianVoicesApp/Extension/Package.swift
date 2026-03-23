// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UkrainianVoicesExtension",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "UkrainianVoicesExtension",
            targets: ["UkrainianVoicesExtension"]
        ),
    ],
    targets: [
        .target(
            name: "UkrainianVoicesExtension",
            dependencies: ["RHVoiceBridge"],
            path: "Provider",
            resources: [
                .copy("../Resources/Voices")
            ]
        ),
        .target(
            name: "RHVoiceBridge",
            path: "Bridge",
            publicHeadersPath: ".",
            cxxSettings: [
                .define("RHVOICE_STATIC")
            ],
            linkerSettings: [
                .linkedLibrary("RHVoice"),
                .linkedLibrary("RHVoice_core"),
                .linkedLibrary("RHVoice_audio"),
                .unsafeFlags(["-L../Libraries"])
            ]
        ),
        .testTarget(
            name: "UkrainianVoicesExtensionTests",
            dependencies: ["UkrainianVoicesExtension"],
            path: "Tests"
        ),
    ],
    cxxLanguageStandard: .cxx17
)
