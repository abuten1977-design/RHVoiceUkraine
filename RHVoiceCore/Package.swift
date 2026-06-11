// swift-tools-version: 5.7

import PackageDescription

let boostHeaderPaths: [CSetting] = [
    .headerSearchPath("external/libs/boost/libs/nowide/include"),
    .headerSearchPath("external/libs/boost/libs/move/include"),
    .headerSearchPath("external/libs/boost/libs/core/include"),
    .headerSearchPath("external/libs/boost/libs/tuple/include"),
    .headerSearchPath("external/libs/boost/libs/config/include"),
    .headerSearchPath("external/libs/boost/libs/array/include"),
    .headerSearchPath("external/libs/boost/libs/unordered/include"),
    .headerSearchPath("external/libs/boost/libs/smart_ptr/include"),
    .headerSearchPath("external/libs/boost/libs/tokenizer/include"),
    .headerSearchPath("external/libs/boost/libs/interprocess/include"),
    .headerSearchPath("external/libs/boost/libs/type_traits/include"),
    .headerSearchPath("external/libs/boost/libs/io/include"),
    .headerSearchPath("external/libs/boost/libs/container_hash/include"),
    .headerSearchPath("external/libs/boost/libs/function/include"),
    .headerSearchPath("external/libs/boost/libs/algorithm/include"),
    .headerSearchPath("external/libs/boost/libs/numeric_conversion/include"),
    .headerSearchPath("external/libs/boost/libs/assert/include"),
    .headerSearchPath("external/libs/boost/libs/date_time/include"),
    .headerSearchPath("external/libs/boost/libs/optional/include"),
    .headerSearchPath("external/libs/boost/libs/container/include"),
    .headerSearchPath("external/libs/boost/libs/system/include"),
    .headerSearchPath("external/libs/boost/libs/concept_check/include"),
    .headerSearchPath("external/libs/boost/libs/variant2/include"),
    .headerSearchPath("external/libs/boost/libs/align/include"),
    .headerSearchPath("external/libs/boost/libs/iterator/include"),
    .headerSearchPath("external/libs/boost/libs/detail/include"),
    .headerSearchPath("external/libs/boost/libs/mp11/include"),
    .headerSearchPath("external/libs/boost/libs/intrusive/include"),
    .headerSearchPath("external/libs/boost/libs/json/include"),
    .headerSearchPath("external/libs/boost/libs/static_assert/include"),
    .headerSearchPath("external/libs/boost/libs/mpl/include"),
    .headerSearchPath("external/libs/boost/libs/mpl/preprocessed/include"),
    .headerSearchPath("external/libs/boost/libs/winapi/include"),
    .headerSearchPath("external/libs/boost/libs/integer/include"),
    .headerSearchPath("external/libs/boost/libs/predef/include"),
    .headerSearchPath("external/libs/boost/libs/range/include"),
    .headerSearchPath("external/libs/boost/libs/bind/include"),
    .headerSearchPath("external/libs/boost/libs/exception/include"),
    .headerSearchPath("external/libs/boost/libs/preprocessor/include"),
    .headerSearchPath("external/libs/boost/libs/throw_exception/include"),
    .headerSearchPath("external/libs/boost/libs/type_index/include"),
    .headerSearchPath("external/libs/boost/libs/lexical_cast/include"),
    .headerSearchPath("external/libs/boost/libs/utility/include"),
]

let rateDefines: [CSetting] = [
    .define("MAX_RATE", to: "5", .when(platforms: [.iOS, .macCatalyst])),
    .define("RHVOICE_MAX_MAX_RATE", to: "5", .when(platforms: [.iOS, .macCatalyst])),
    .define("MAX_RATE", to: "20", .when(platforms: [.macOS])),
    .define("RHVOICE_MAX_MAX_RATE", to: "20", .when(platforms: [.macOS])),
]

let commonDefines: [CSetting] = rateDefines + [
    .define("RHVOICE"),
    .define("PACKAGE", to: "\"RHVoice\""),
    .define("DATA_PATH", to: "\"\""),
    .define("CONFIG_PATH", to: "\"\""),
    .unsafeFlags(["-Wno-enum-constexpr-conversion", "-D_LIBCPP_ENABLE_CXX17_REMOVED_UNARY_BINARY_FUNCTION"]),
    .define("TARGET_OS_IPHONE", .when(platforms: [.iOS, .macCatalyst])),
    .define("ANDROID", .when(platforms: [.iOS, .macCatalyst])),
    .define("TARGET_OS_MAC", .when(platforms: [.macOS])),
]

let rhvoiceHeaderPaths: [CSetting] = [
    .headerSearchPath("src/third-party/utf8"),
    .headerSearchPath("src/third-party/rapidxml"),
    .headerSearchPath("external/libs/sonic"),
    .headerSearchPath("src/include"),
    .headerSearchPath("src/hts_engine"),
]

let coreSettings: [CSetting] = boostHeaderPaths + rhvoiceHeaderPaths + commonDefines

let package = Package(
    name: "RHVoiceCore",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "RHVoiceBridge",
            targets: ["RHVoiceBridge"]
        )
    ],
    targets: [
        .target(
            name: "RHVoiceCoreEngine",
            path: "RHVoice",
            exclude: [
                "src/core/unidata.cpp",
                "src/core/userdict_parser.c",
                "src/core/emoji_data.cpp",
                "src/audio/libao.cpp",
                "src/audio/portaudio.cpp",
                "src/audio/pulse.cpp",
                "src/core/CMakeLists.txt",
                "src/core/CMakeLists.txt.bak",
                "src/hts_engine/CMakeLists.txt",
                "src/hts_engine/CMakeLists.txt.bak",
                "src/audio/CMakeLists.txt",
                "src/audio/CMakeLists.txt.bak",
                "src/lib/CMakeLists.txt",
                "src/lib/CMakeLists.txt.bak",
                "src/audio/SConscript",
                "src/core/SConscript",
                "src/hts_engine/SConscript",
                "src/lib/SConscript",
                "src/core/config.h.in",
                "src/core/userdict_parser.g",
                "src/core/.gitignore",
                "src/lib/lib.def",
            ],
            sources: [
                "src/core",
                "src/hts_engine",
                "src/lib",
                "src/audio",
                "external/libs/sonic/sonic.c",
            ],
            publicHeadersPath: "src/include/",
            cSettings: [
                .headerSearchPath("../Bridge/Mock"),
                .define("VERSION", to: "\"1.16.4\""),
                .define("ENABLE_SONIC", to: "1"),
            ] + coreSettings
        ),
        .target(
            name: "RHVoiceBridge",
            dependencies: ["RHVoiceCoreEngine"],
            path: "Bridge",
            exclude: [
                "Mock",
            ],
            sources: [
                "Sources",
            ],
            publicHeadersPath: "PublicHeaders",
            cSettings: [
                .headerSearchPath("PublicHeaders"),
                .headerSearchPath("PrivateHeaders"),
            ] + coreSettings,
            linkerSettings: [
                .linkedFramework("AVFoundation"),
            ]
        ),
    ],
    cLanguageStandard: .c11,
    cxxLanguageStandard: .cxx17
)
