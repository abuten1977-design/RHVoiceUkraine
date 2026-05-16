// swift-tools-version: 5.7

import PackageDescription

let boostHeaderPaths: [CSetting] = [
    .headerSearchPath("../RHVoice/external/libs/boost/libs/nowide/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/move/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/core/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/tuple/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/config/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/array/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/unordered/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/smart_ptr/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/tokenizer/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/interprocess/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/type_traits/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/io/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/container_hash/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/function/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/algorithm/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/numeric_conversion/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/assert/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/date_time/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/optional/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/container/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/system/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/concept_check/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/variant2/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/align/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/iterator/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/detail/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/mp11/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/intrusive/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/json/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/static_assert/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/mpl/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/mpl/preprocessed/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/winapi/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/integer/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/predef/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/range/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/bind/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/exception/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/preprocessor/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/throw_exception/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/type_index/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/lexical_cast/include"),
    .headerSearchPath("../RHVoice/external/libs/boost/libs/utility/include"),
]

let commonDefines: [CSetting] = [
    .define("MAX_RATE", to: "3"),
    .define("RHVOICE_MAX_MAX_RATE", to: "12", .when(platforms: [.macOS])),
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
    .headerSearchPath("../RHVoice/src/third-party/utf8"),
    .headerSearchPath("../RHVoice/src/third-party/rapidxml"),
    .headerSearchPath("../RHVoice/external/libs/sonic"),
    .headerSearchPath("../RHVoice/src/include"),
    .headerSearchPath("../RHVoice/src/hts_engine"),
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
