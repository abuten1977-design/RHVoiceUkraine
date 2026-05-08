# SPM Refactoring Plan: Compile RHVoice C++ from Source

## Summary

Replace pre-built static libraries (`libRHVoice.a`, `libRHVoice_core.a`, `libRHVoice_audio.a`) with a local SPM package that compiles the C++ engine from source, following the approach used by the Polish project (rhvoice-ee).

---

## A. SPM Package to Create

**Path:** `RHVoiceUkraine/RHVoiceCore/Package.swift`

**Package name:** `RHVoiceCore`

**Targets:**
1. `RHVoiceCoreEngine` — C/C++ target compiling the engine from `../RHVoice/` sources
2. `RHVoiceBridge` — Objective-C/C++ bridge target exposing the engine to Swift (equivalent to Polish project's `RHVoice` target in `Core/Bridge/`)

**Products:**
- `.library(name: "RHVoiceBridge", targets: ["RHVoiceBridge"])` — what the app/extension will import

---

## B. C++ Source Files to Include

### Source directories (relative to `../RHVoice/` from Package.swift):

```
sources: [
    "src/core",
    "src/hts_engine",
    "src/pkg",
    "src/lib",
    "src/audio"
]
```

### Files to EXCLUDE (same as Polish project):

```swift
exclude: [
    // Included into other sources directly (not standalone compilation units)
    "src/core/unidata.cpp",
    "src/core/userdict_parser.c",
    "src/core/emoji_data.cpp",
    // Platform-specific audio backends (Linux/Windows only)
    "src/audio/libao.cpp",
    "src/audio/portaudio.cpp",
    "src/audio/pulse.cpp",
    // Build system files
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
    "src/pkg/SConscript",
    // Not used on Apple platforms
    "src/core/config.h.in",
    "src/core/userdict_parser.g",
    "src/core/.gitignore",
    "src/lib/lib.def"
]
```

### Public headers path:
```
publicHeadersPath: "src/include/"
```

---

## C. Compiler Flags/Defines (from Polish Package.swift)

```swift
let commonDefines: [CSetting] = [
    .define("MAX_RATE", to: "3"),
    .define("RHVOICE"),
    .define("PACKAGE", to: "\"RHVoice\""),
    .define("ENABLE_PKG"),
    .define("DATA_PATH", to: ""),
    .define("CONFIG_PATH", to: ""),
    .unsafeFlags(["-Wno-enum-constexpr-conversion"]),
    .define("TARGET_OS_IPHONE", .when(platforms: [.iOS, .macCatalyst])),
    .define("ANDROID", .when(platforms: [.iOS, .macCatalyst])),  // needed for root cert loading
    .define("TARGET_OS_MAC", .when(platforms: [.macOS])),
    .define("VERSION", to: "\"1.16.4\""),
]
```

### Header search paths (relative to the RHVoice source root):

```swift
// Boost headers (all individual lib include dirs)
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

// RHVoice internal headers
.headerSearchPath("src/third-party/utf8"),
.headerSearchPath("src/third-party/rapidxml"),
.headerSearchPath("src/include"),
.headerSearchPath("src/hts_engine"),
```

### Language standards:
```swift
cLanguageStandard: .c11,
cxxLanguageStandard: .cxx11
```

---

## D. Changes to project.yml — iOS Extension Target (`UkrainianVoicesExtension`)

### Remove:
```yaml
# Remove these settings:
LIBRARY_SEARCH_PATHS: "$(SRCROOT)/Extension/Libraries"
OTHER_LDFLAGS: "-lRHVoice -lRHVoice_core -lRHVoice_audio -lstdc++"
```

### Add:
```yaml
dependencies:
  - package: RHVoiceCore
    product: RHVoiceBridge
  # Keep existing:
  - sdk: AVFoundation.framework
  - sdk: AVFAudio.framework
  - sdk: AudioToolbox.framework
```

### Add package reference at project level:
```yaml
packages:
  RHVoiceCore:
    path: ../RHVoiceCore
```

---

## E. Changes to project.yml — RHVoiceKit iOS Framework

### Remove:
```yaml
# Remove these settings from RHVoiceKit:
LIBRARY_SEARCH_PATHS: "$(SRCROOT)/Extension/Libraries"
OTHER_LDFLAGS: "-lRHVoice -lRHVoice_core -lRHVoice_audio"
```

### Add:
```yaml
dependencies:
  - package: RHVoiceCore
    product: RHVoiceBridge
  # Keep existing:
  - sdk: AVFoundation.framework
  - sdk: AVFAudio.framework
```

### Simplify HEADER_SEARCH_PATHS:
The SPM package will expose public headers via its module, so `RHVoiceKit` only needs to `#import <RHVoiceBridge/...>` or use the module map. The current `HEADER_SEARCH_PATHS` pointing to `RHVoice/src/include` can be removed once the bridge module is properly set up.

---

## F. Header Search Paths Needed

### In the SPM Package (RHVoiceCoreEngine target):
All boost and internal headers listed in section C above.

### In the SPM Package (RHVoiceBridge target):
```swift
cSettings: [
    .headerSearchPath("PrivateHeaders"),  // internal bridge headers
    // Plus all the same boost + RHVoice headers with "../RHVoice/" prefix
]
```

### In project.yml targets (after migration):
**None needed** — SPM handles header visibility through module maps. The `RHVoiceKit` sources will `#import <RHVoiceBridge/RHVoiceBridge.h>` (or equivalent umbrella header).

---

## G. Step-by-Step Implementation Order

### Step 1: Create the SPM Package directory structure
```
RHVoiceUkraine/
├── RHVoiceCore/
│   ├── Package.swift
│   └── Bridge/
│       ├── Sources/          (Obj-C++ bridge files)
│       ├── PublicHeaders/    (headers exposed to Swift)
│       ├── PrivateHeaders/   (internal headers)
│       └── Mock/
│           └── config.h      (empty file, required by Polish project)
```

### Step 2: Write Package.swift
- Define `RHVoiceCoreEngine` target pointing to `../RHVoice/` with correct sources/excludes
- Define `RHVoiceBridge` target with Obj-C++ wrapper code
- Add binary targets for libcurl/libssl/libcrypto (if ENABLE_PKG is needed for iOS)
- Set all cSettings (defines, header search paths, unsafe flags)

### Step 3: Create the Bridge layer
Either:
- **Option A (recommended):** Copy the Polish project's `Core/Bridge/` directory and adapt it. It already has a working Obj-C++ bridge (`RHVoiceBridge.mm`, `RHSpeechSynthesizer.mm`, etc.) that exposes the C++ engine to Swift via clean Obj-C headers.
- **Option B:** Keep our existing `RHVoiceKit/Sources/RHVoiceEngine.mm` as the bridge, but restructure it to work as an SPM target.

### Step 4: Create `config.h` mock
Create `RHVoiceCore/Bridge/Mock/config.h` as an empty file (the Polish project does this — the real config is set via compiler defines).

### Step 5: Verify SPM package builds standalone
```bash
cd RHVoiceCore
swift build
```

### Step 6: Update project.yml
- Add `packages:` section with local path reference
- Remove `LIBRARY_SEARCH_PATHS` and `OTHER_LDFLAGS` from iOS targets
- Add SPM dependency to `RHVoiceKit` and `UkrainianVoicesExtension`
- Remove the `RHVoiceKit` target's dependency on static libs

### Step 7: Update RHVoiceKit imports
Change `#include "RHVoice.h"` to `#import <RHVoiceBridge/RHVoiceBridge.h>` (or whatever the module umbrella is).

### Step 8: Regenerate Xcode project and build
```bash
cd UkrainianVoicesApp
xcodegen generate
xcodebuild -scheme UkrainianVoicesExtension -sdk iphoneos build
```

### Step 9: Remove static libraries
Delete `UkrainianVoicesApp/Extension/Libraries/*.a` and `*.dylib` files.

### Step 10: Test on device
Verify the extension loads and synthesizes speech correctly.

---

## H. What Could Go Wrong & How to Verify

### 1. Missing source files or wrong excludes
**Symptom:** Undefined symbols at link time.
**Fix:** Compare our `src/core/*.cpp` file list with the Polish project's. Ensure no file is accidentally excluded.
**Verify:** `nm` on the built library to check all expected symbols are present.

### 2. Header search path issues
**Symptom:** `#include <boost/...>` or `#include "core/..."` fails.
**Fix:** Our boost is at `RHVoice/external/libs/boost/libs/*/include` (same structure as Polish). Ensure all paths are listed. We also have `RHVoice/external/libs/boost/unified_include` which could be used as a single path instead of individual lib paths.
**Verify:** `swift build` in the package directory.

### 3. config.h conflict
**Symptom:** Our `RHVoice/src/core/config.h` (which has real content: `#define ENABLE_PKG 1` etc.) may conflict with the mock.
**Fix:** The Polish project uses `Bridge/Mock/config.h` (empty) and passes all defines via compiler flags. We need to ensure the SPM target's header search path finds the mock BEFORE the real `src/core/config.h`, OR we remove the real one from the source tree and rely purely on defines.
**Verify:** Check that `ENABLE_PKG` is defined via cSettings, not via the file.

### 4. ENABLE_PKG and curl dependency
**Symptom:** If `ENABLE_PKG` is defined, the code tries to use libcurl for package downloads.
**Fix:** The Polish project includes binary xcframework targets for libcurl, libssl, libcrypto, libnghttp2. We need to either:
- Include the same binary targets (recommended for full feature parity)
- OR disable `ENABLE_PKG` if we don't need online voice downloads on iOS
**Verify:** Build with and without `ENABLE_PKG` define.

### 5. C++ standard mismatch
**Symptom:** Compilation errors with C++11 vs C++17.
**Fix:** The Polish project uses `cxxLanguageStandard: .cxx11`. Our macOS target uses C++17. The RHVoice source should compile with C++11. Use `.cxx11` to match the Polish project.
**Verify:** Clean build.

### 6. Architecture issues (arm64 vs x86_64)
**Symptom:** SPM builds for wrong architecture.
**Fix:** SPM respects the Xcode build settings for destination. Ensure the package doesn't have platform restrictions that exclude iOS.
**Verify:** Build for both simulator (x86_64/arm64) and device (arm64).

### 7. Module name collision
**Symptom:** `import RHVoice` conflicts between our module and the Polish project's if both are referenced.
**Fix:** Name our module differently (e.g., `RHVoiceBridge` or `RHVoiceEngine`).
**Verify:** Clean build with no ambiguous module imports.

### 8. Sonic library missing
**Symptom:** Undefined symbols for `sonicCreateStream`, etc.
**Fix:** The Polish project does NOT include sonic in their SPM package (they don't define `ENABLE_SONIC`). Our macOS target does include sonic. Decision: either add sonic as a source in the SPM package, or don't define `ENABLE_SONIC` for iOS (the Polish project doesn't use it).
**Verify:** Check if Ukrainian voice quality requires sonic. If not needed, omit it.

---

## How the Polish Project's Swift Code Calls C++ Engine

The Polish project does **NOT** use a bridging header. Instead:

1. **SPM module map**: The `RHVoice` target in `Core/Package.swift` has `publicHeadersPath: "RHVoice/PublicHeaders/"` which exposes Obj-C headers as a module.

2. **Import in Swift**: Extension code does `import RHVoice` which gives access to all Obj-C classes defined in the public headers:
   - `RHVoiceBridge` — singleton for engine init/teardown
   - `RHSpeechSynthesizer` — performs synthesis
   - `RHSpeechSynthesisVoice` — voice metadata
   - `RHSpeechUtterance` — text to synthesize
   - `RHVoiceBridgeParams` — configuration

3. **Bridge layer** (`Core/Bridge/`): Obj-C++ files (`.mm`) wrap the C++ API (`RHVoice.h`) into clean Obj-C classes. The C++ headers are only visible inside the bridge target, not exposed to Swift consumers.

4. **No bridging header needed** because SPM generates module maps automatically from the `publicHeadersPath`.

---

## Path Mapping: Polish Project → Our Project

| Polish project path | Our project equivalent |
|---|---|
| `Core/Core/src/core/` | `RHVoice/src/core/` |
| `Core/Core/src/hts_engine/` | `RHVoice/src/hts_engine/` |
| `Core/Core/src/lib/` | `RHVoice/src/lib/` |
| `Core/Core/src/audio/` | `RHVoice/src/audio/` |
| `Core/Core/src/pkg/` | `RHVoice/src/pkg/` |
| `Core/Core/src/include/` | `RHVoice/src/include/` |
| `Core/Core/src/third-party/utf8/` | `RHVoice/src/third-party/utf8/` |
| `Core/Core/src/third-party/rapidxml/` | `RHVoice/src/third-party/rapidxml/` |
| `Core/Core/external/libs/boost/` | `RHVoice/external/libs/boost/` |
| `Core/Core/SConstruct` | `RHVoice/SConstruct` |
| `Core/Bridge/` | **NEW: `RHVoiceCore/Bridge/`** (to be created) |
| `Core/Bridge/Mock/config.h` | **NEW: `RHVoiceCore/Bridge/Mock/config.h`** (empty) |

---

## Key Difference from Polish Project

The Polish project has `Core/` as a **subdirectory** containing both the SPM package AND the RHVoice source (as a git submodule at `Core/Core/`). Their Package.swift path is `Core/Package.swift` and it references sources at `Core/` (which resolves to `Core/Core/src/...`).

We will create `RHVoiceCore/Package.swift` and reference sources at `../RHVoice/` (going up one level to reach the RHVoice source directory). All header search paths must use this `../RHVoice/` prefix.

---

## Estimated Effort

- Step 1-4: ~2 hours (create package structure, write Package.swift, copy/adapt bridge)
- Step 5: ~1-2 hours (debug compilation issues)
- Step 6-7: ~30 minutes (update project.yml)
- Step 8-10: ~1-2 hours (build, fix issues, test)

**Total: ~5-7 hours**
