// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RHVoiceUkrainianSynthesizer",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "RHVoiceUkrainianSynthesizer",
            targets: ["RHVoiceUkrainianSynthesizer"]
        ),
    ],
    targets: [
        .target(
            name: "RHVoiceUkrainianSynthesizer",
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
                .headerSearchPath("../../RHVoice/src/include"),
                .define("RHVOICE_STATIC")
            ],
            linkerSettings: [
                .linkedLibrary("RHVoice", .when(platforms: [.iOS])),
                .linkedLibrary("RHVoice_core", .when(platforms: [.iOS])),
                .linkedLibrary("RHVoice_audio", .when(platforms: [.iOS])),
                .unsafeFlags(["-L../Libraries"])
            ]
        ),
        .testTarget(
            name: "RHVoiceUkrainianSynthesizerTests",
            dependencies: ["RHVoiceUkrainianSynthesizer"],
            path: "Tests"
        ),
    ],
    cxxLanguageStandard: .cxx17
)
