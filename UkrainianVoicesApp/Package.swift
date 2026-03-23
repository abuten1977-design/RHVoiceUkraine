// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RHVoiceOfficial",
    defaultLocalization: "en",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .executable(name: "RHVoiceApp", targets: ["RHVoiceApp"]),
        .library(name: "RHVoiceExtension", type: .dynamic, targets: ["Extension"])
    ],
    dependencies: [
        // Предполагаем, что Core находится в подпапке и содержит C++ движок
        .package(path: "./Core")
    ],
    targets: [
        .target(
            name: "Common",
            dependencies: [
                .product(name: "RHVoice", package: "Core")
            ],
            path: "Common",
            resources: [
                .process("Resources") // Для хранения данных и базовых настроек
            ],
            swiftSettings: [.define("MACOS")]
        ),
        .target(
            name: "RHVoiceBridge",
            dependencies: [
                .product(name: "RHVoice", package: "Core")
            ],
            path: "Bridge",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("../Core/Core/src/include"),
                .define("RHVOICE_MOBILE")
            ]
        ),
        .target(
            name: "Extension",
            dependencies: [
                "Common",
                "RHVoiceBridge"
            ],
            path: "Extension",
            exclude: ["Tests"],
            resources: [
                .process("Voices") // Голоса должны быть доступны расширению напрямую
            ],
            swiftSettings: [.define("MACOS")]
        ),
        .executableTarget(
            name: "RHVoiceApp",
            dependencies: [
                "Common",
                "Extension",
                "RHVoiceBridge"
            ],
            path: "App",
            swiftSettings: [.define("MACOS")]
        )
    ]
)
