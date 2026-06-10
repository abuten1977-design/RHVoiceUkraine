# iOS SPM Build Analysis: eSpeak-NG vs RHVoiceUkraine

**Date:** 2026-05-08  
**Purpose:** Understand why our iOS extension fails to build with SPM and how eSpeak-NG does it correctly.

---

## 1. How eSpeak-NG Structures Their SPM Package

**Repository:** `https://github.com/espeak-ng/espeak-ng-spm.git`

```swift
// swift-tools-version: 6.2
let package = Package(
    name: "espeak-ng",
    products: [
        .library(name: "libespeak-ng", targets: ["libespeak-ng"]),
        .library(name: "espeak-ng-data", targets: ["data"]),
    ],
    targets: [
        .target(name: "libsonic", exclude: ["_repo"]),
        .target(name: "libucd"),
        .target(name: "data", resources: [
            .copy("espeak-ng-data"),
            .copy("phsource"),
            .copy("dictsource"),
        ]),
        .target(
            name: "libespeak-ng",
            dependencies: ["libsonic", "libucd"],
            exclude: ["_repo"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("_repo/src/include"),
                .define("ESPEAK_NG_API", to: ""),
                .define("N_PATH_HOME", to: "1024"),
            ]
        ),
    ]
)
```

**Key design decisions:**
- **Remote SPM package** — the C/C++ engine lives in a separate git repo (`espeak-ng-spm`), not a local path
- **Simple flat structure** — 3 C targets + 1 resource target, no Objective-C++ bridge
- **No bridging layer** — Swift imports the C module directly via SPM's auto-generated module map
- **`publicHeadersPath: "include"`** — exposes C headers as a Swift-importable module
- **Resources as a separate product** — `espeak-ng-data` is a separate library target with `.copy()` resources

---

## 2. How the iOS Extension References the SPM Package

In `EspeakNg.xcodeproj/project.pbxproj`:

```
// Project-level package reference
packageReferences = (
    D003ED21290EC704004DF9D8 /* XCRemoteSwiftPackageReference "espeak-ng-spm" */,
);

// Extension target's package product dependencies
packageProductDependencies = (
    D003ED2B290EC712004DF9D8 /* libespeak-ng */,
    D0CFEDC12916672700955B1F /* espeak-ng-data */,
);

// Extension's Frameworks build phase
files = (
    D0CFEDC22916672700955B1F /* espeak-ng-data in Frameworks */,
    D003ED2C290EC712004DF9D8 /* libespeak-ng in Frameworks */,
);
```

**Key observations:**
- The **extension target directly depends on SPM products** — no intermediate framework
- The **app target does NOT link the SPM package** — only the extension does
- SPM products appear in the extension's "Frameworks" build phase
- Xcode handles building the SPM targets automatically as part of the dependency graph

---

## 3. Linker Settings

eSpeak-NG uses **NO special linker flags**:
- No `OTHER_LDFLAGS`
- No `LIBRARY_SEARCH_PATHS`
- No `-lstdc++` or `-lc++`
- No manual library paths

The extension build settings are minimal:
```
CODE_SIGN_ENTITLEMENTS = Project/Ext.entitlements;
GENERATE_INFOPLIST_FILE = YES;
INFOPLIST_FILE = Extension/Info.plist;
LD_RUNPATH_SEARCH_PATHS = (
    "$(inherited)",
    "@executable_path/Frameworks",
    "@executable_path/../../Frameworks",
);
PRODUCT_BUNDLE_IDENTIFIER = "dj.phoenix.espeak-ng.synth-ext";
SKIP_INSTALL = YES;
```

**Why no `-lc++`?** Because the SPM package is pure C (not C++). The C library is statically linked by SPM automatically. SPM handles all linker flags internally when it builds the C targets.

---

## 4. Swift-to-C Bridge Approach

**eSpeak-NG uses SPM's auto-generated module map — NO bridging header.**

In `Extension/SynthAudioUnit.swift`:
```swift
import libespeak_ng  // Direct import of SPM C module
```

This works because:
1. The SPM target `libespeak-ng` has `publicHeadersPath: "include"`
2. SPM auto-generates a `module.modulemap` for the C target
3. Swift can directly import the C module by its target name (with `-` replaced by `_`)

**No bridging header, no manual module map, no Objective-C++ wrapper.**

---

## 5. Extension Binary Linkage

No pre-built binary available to run `otool -L` on (project needs to be built with signing). Based on the project structure:

- Extension links **statically** against `libespeak-ng` (SPM default for C targets)
- Extension links **statically** against `libsonic` and `libucd` (transitive deps)
- `espeak-ng-data` provides bundled resources (`.bundle` in the appex)
- System frameworks: only `AVFoundation`, `CoreAudioKit`, `Accelerate`, `OSLog`

---

## 6. Special Build Phases / Scripts

**None.** eSpeak-NG has:
- No pre-build scripts
- No post-build scripts
- No "Copy Files" phases (except the standard "Embed Foundation Extensions" for the appex)
- No manual resource copying

Resources are handled entirely by SPM's `.copy()` resource rules.

---

## 7. Our Project: Current State & Problems

### Our `RHVoiceCore/Package.swift`

We have a well-structured local SPM package with two targets:
- `RHVoiceCoreEngine` — C/C++ engine compiled from `../RHVoice/` sources
- `RHVoiceBridge` — Objective-C++ bridge exposing `RHVoiceEngine` class to Swift

The package compiles successfully standalone (`swift build` in RHVoiceCore/).

### Our `project.yml` Extension Target

```yaml
UkrainianVoicesExtension:
  type: app-extension
  platform: iOS
  sources:
    - Shared
    - Extension/Provider
  dependencies:
    - package: RHVoiceCore
      product: RHVoiceBridge
    - target: RHVoiceKit
      embed: false
    - sdk: AVFoundation.framework
    - sdk: AVFAudio.framework
    - sdk: AudioToolbox.framework
```

### The Build Error

```
fatal error: module map file '.../build/GeneratedModuleMaps-iphoneos/RHVoiceCoreEngine.modulemap' not found
```

**Root cause:** The `GeneratedModuleMaps-iphoneos/` directory is never created in the `UkrainianVoicesApp/build/` directory. It exists in `RHVoiceCore/build/` (from a previous standalone build), but Xcode expects it in the project's own build directory.

This happens because:
1. The SPM package is referenced as a **local path** (`path: ../RHVoiceCore`)
2. Xcode resolves the package graph correctly ("Resolved source packages: RHVoiceCore")
3. But the SPM targets fail to compile before the dependent Xcode targets start
4. The `RHVoiceKit` framework target (which depends on `RHVoiceBridge`) starts compiling its `.mm` files before SPM has generated the module maps

### Additional Warning

```
warning: Multiple targets match implicit dependency for product reference 'RHVoiceKit.framework'.
Consider adding an explicit dependency on the intended target to resolve this ambiguity.
    note: Target 'RHVoiceKit' (in project 'UkrainianVoices')
    note: Target 'RHVoiceKitMac' (in project 'UkrainianVoices')
```

Both `RHVoiceKit` (iOS) and `RHVoiceKitMac` (macOS) produce `RHVoiceKit.framework`, causing ambiguity.

---

## 8. What eSpeak Does Right (That We Don't)

| Aspect | eSpeak-NG | Our Project |
|--------|-----------|-------------|
| SPM package location | Remote git repo | Local path (`../RHVoiceCore`) |
| Extension → C bridge | Direct `import libespeak_ng` (C module) | Via `RHVoiceKit` framework (Obj-C++) |
| Intermediate framework | None — extension links SPM directly | `RHVoiceKit` framework sits between extension and SPM |
| C++ in SPM package | No C++ (pure C) | Heavy C++ (boost, STL) |
| Bridging approach | SPM auto-modulemap | Obj-C++ bridge + framework headers |
| Build complexity | 2 targets (app + extension) | 6+ targets (app, ext, framework ×2, macOS variants) |
| Linker flags | None needed | Needs `-lc++` for C++ runtime |
| Resource handling | SPM `.copy()` resources | Manual post-build script |

---

## 9. What We're Missing / Doing Wrong

### Problem 1: SPM Module Maps Not Generated Before Framework Compilation

The `RHVoiceKit` target depends on `RHVoiceBridge` (SPM product), but Xcode's build system isn't building the SPM targets first. The `-fmodule-map-file=.../GeneratedModuleMaps-iphoneos/RHVoiceCoreEngine.modulemap` flag is passed to clang, but the file doesn't exist yet.

**Why:** When using xcodegen with a local SPM package, the build order isn't always correctly inferred. The `RHVoiceKit` framework target lists `RHVoiceBridge` as a dependency, but xcodegen may not generate the correct implicit dependency that forces SPM compilation first.

### Problem 2: Dual Architecture (RHVoiceKit + RHVoiceKitMac) Ambiguity

Both targets produce `RHVoiceKit.framework` with `PRODUCT_NAME: RHVoiceKit`. Xcode can't resolve which one the extension should use.

### Problem 3: Missing `-lc++` Linker Flag

Our SPM package compiles C++ code. The extension (and RHVoiceKit framework) need to link against the C++ standard library. eSpeak doesn't need this because it's pure C.

### Problem 4: Unnecessary Indirection

eSpeak's extension imports the C library directly. Our extension goes through:
```
Extension → RHVoiceKit.framework → RHVoiceBridge (SPM) → RHVoiceCoreEngine (SPM)
```

This extra framework layer creates build ordering issues that wouldn't exist if the extension linked SPM directly.

---

## 10. Exact Changes Needed

### Fix 1: Ensure SPM Builds Before RHVoiceKit (Critical)

**Option A (Recommended):** Remove the `RHVoiceKit` framework for iOS entirely. Have the extension depend directly on the SPM package:

```yaml
UkrainianVoicesExtension:
  dependencies:
    - package: RHVoiceCore
      product: RHVoiceBridge
    # Remove: - target: RHVoiceKit
```

The extension's Swift code already does `import RHVoiceKit`, but it could instead `import RHVoiceBridge` directly (the SPM module exposes the same headers).

**Option B (Minimal change):** Add an explicit dependency in `RHVoiceKit` target settings to force SPM compilation first. In `project.yml`, add to `RHVoiceKit`:

```yaml
settings:
  base:
    # ... existing settings ...
  configs:
    Debug:
      OTHER_LDFLAGS: "-lc++"
    Release:
      OTHER_LDFLAGS: "-lc++"
```

And ensure the build system knows about the dependency by using `-derivedDataPath` consistently or building with `xcodebuild -scheme UkrainianVoices` (the app scheme, which includes all targets in correct order).

### Fix 2: Resolve Framework Name Ambiguity

Rename `RHVoiceKitMac` to produce a different product name:

```yaml
RHVoiceKitMac:
  settings:
    base:
      PRODUCT_NAME: RHVoiceKitMac  # Instead of RHVoiceKit
```

Or add explicit dependency in the extension target:

```yaml
UkrainianVoicesExtension:
  dependencies:
    - target: RHVoiceKit
      embed: false
      # This makes the dependency explicit, resolving ambiguity
```

### Fix 3: Add C++ Standard Library Linker Flag

In `project.yml`, for both `RHVoiceKit` and `UkrainianVoicesExtension`:

```yaml
settings:
  base:
    OTHER_LDFLAGS: "$(inherited) -lc++"
```

This is needed because `RHVoiceCoreEngine` is C++ and the linker needs `libc++`.

### Fix 4: Build with Scheme, Not Target

Instead of:
```bash
xcodebuild -target UkrainianVoicesExtension ...
```

Use:
```bash
xcodebuild -scheme UkrainianVoices ...
```

Building the app scheme ensures all dependencies (including SPM packages) are built in the correct order. Building a single target may skip SPM compilation.

### Fix 5: Clean Build Directory

The stale `build/` directory may have cached incorrect paths. Before rebuilding:
```bash
rm -rf UkrainianVoicesApp/build
```

---

## 11. Test Build Errors (Actual Output)

```
fatal error: module map file '/Users/andriybutenko/Projects/RHVoiceUkraine/UkrainianVoicesApp/build/GeneratedModuleMaps-iphoneos/RHVoiceCoreEngine.modulemap' not found
fatal error: module map file '/Users/andriybutenko/Projects/RHVoiceUkraine/UkrainianVoicesApp/build/GeneratedModuleMaps-iphoneos/RHVoiceBridge.modulemap' not found

warning: Multiple targets match implicit dependency for product reference 'RHVoiceKit.framework'.

** BUILD FAILED **
```

**Diagnosis:** The SPM package targets (`RHVoiceCoreEngine`, `RHVoiceBridge`) were never compiled during this build. Xcode resolved the package graph but didn't schedule the SPM compilation before the `RHVoiceKit` framework target started. This is a build ordering / dependency graph issue specific to xcodegen-generated projects with local SPM packages.

---

## 12. Recommended Architecture (Following eSpeak's Pattern)

The cleanest solution, following eSpeak-NG's proven approach:

1. **Extension links SPM directly** — no intermediate framework for iOS
2. **App links nothing** — communicates with extension via AudioUnit XPC
3. **SPM package provides everything** — compiled C++ engine + Obj-C++ bridge + public headers
4. **No bridging header** — use SPM's module map system
5. **Resources via SPM** — use `.copy()` for voice data instead of post-build scripts

```
UkrainianVoices.app (no C++ linkage)
└── PlugIns/
    └── UkrainianVoicesExtension.appex
        ├── links: RHVoiceBridge (static, from SPM)
        │   └── links: RHVoiceCoreEngine (static, from SPM)
        └── RHVoiceData/ (copied via script or SPM resources)
```

This eliminates:
- The `RHVoiceKit` framework target entirely (for iOS)
- Build ordering issues
- Framework embedding complexity
- The "multiple targets match" ambiguity

The extension's Swift code would do:
```swift
import RHVoiceBridge  // SPM module, auto-generated modulemap
```

Instead of the current:
```swift
import RHVoiceKit  // Framework that wraps SPM
```
