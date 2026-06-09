# RHVoice Ukrainian — Code Structure Map

Generated: 2026-05-07

---

## 1. iOS Extension (UkrainianVoicesExtension target)

Platform: iOS 16.0 | Type: `app-extension` (AudioUnit speech synthesizer)

### Source Files

| Path | Purpose | Key Classes/Functions |
|------|---------|---------------------|
| `UkrainianVoicesApp/Extension/Provider/UkrainianSpeechSynthesizer.swift` | Main AudioUnit — receives VoiceOver requests, calls RHVoiceEngine, renders PCM audio | `UkrainianSpeechSynthesizer: AVSpeechSynthesisProviderAudioUnit` — `synthesizeSpeechRequest()`, `cancelSpeechRequest()`, `performRender()`, `internalRenderBlock` |
| `UkrainianVoicesApp/Extension/Provider/AudioUnitFactory.swift` | NSExtension entry point — instantiates the AudioUnit | `AudioUnitFactory: AUAudioUnitFactory` — `createAudioUnit(with:)` |
| `UkrainianVoicesApp/Shared/RHVoiceSharedSettings.swift` | Settings model, voice catalog, App Group persistence (shared with App) | `RHVoiceSharedSettings`, `RHVoiceSharedSettingsSnapshot`, `RHVoiceSharedSettingsStore` — `loadSnapshot()`, `saveSnapshot()` |
| `UkrainianVoicesApp/Shared/RHVoiceSynthesisRuntime.swift` | Synthesis request/state machine types (shared with App) | `RHVoiceSynthesisRequest`, `RHVoiceSessionToken`, `RHVoiceSynthesisState`, `RHVoiceRuntimeCoordinator`, `RHVoiceSynthesisRequestFactory` |

### Config Files

| Path | Purpose |
|------|---------|
| `UkrainianVoicesApp/Extension/Info-iOS.plist` | Extension manifest — declares AudioUnit type `ausp`, subtype `rhvc`, manufacturer `RHVo`, principal class `AudioUnitFactory` |
| `UkrainianVoicesApp/Extension/UkrainianVoicesExtension.entitlements` | App Group entitlement for shared settings |

### Dependencies

- **RHVoiceKit** framework (embedded: false — linked only)
- Static libraries: `libRHVoice.a`, `libRHVoice_core.a`, `libRHVoice_audio.a` (from `Extension/Libraries/`)
- Frameworks: AVFoundation, AVFAudio, AudioToolbox

---

## 2. macOS Extension (UkrainianVoicesExtensionMac target)

Platform: macOS 13.0 | Type: `app-extension` (AudioUnit speech synthesizer)

### Source Files

**Identical Swift sources** to iOS extension (same `sources:` in project.yml):

| Path | Purpose | Key Classes/Functions |
|------|---------|---------------------|
| `UkrainianVoicesApp/Extension/Provider/UkrainianSpeechSynthesizer.swift` | Same AudioUnit as iOS | `UkrainianSpeechSynthesizer` |
| `UkrainianVoicesApp/Extension/Provider/AudioUnitFactory.swift` | Same factory | `AudioUnitFactory` |
| `UkrainianVoicesApp/Shared/RHVoiceSharedSettings.swift` | Shared settings | `RHVoiceSharedSettingsStore` |
| `UkrainianVoicesApp/Shared/RHVoiceSynthesisRuntime.swift` | Shared runtime types | `RHVoiceRuntimeCoordinator` |

### Config Files

| Path | Purpose |
|------|---------|
| `UkrainianVoicesApp/Extension/Info.plist` | macOS extension manifest — AudioUnit `ausp`/`rhvc`/`RHVo`, resourceBundleID for macOS |
| `UkrainianVoicesApp/Extension/UkrainianVoicesExtensionMac.entitlements` | App sandbox + App Group |

### Dependencies

- **RHVoiceKitMac** framework (embedded: true) — this is the key difference: macOS compiles C++ engine source directly into the framework
- Frameworks: AVFoundation, AVFAudio, AudioToolbox, CoreAudio, CoreAudioKit

---

## 3. RHVoiceKit Framework

Two targets: `RHVoiceKit` (iOS) and `RHVoiceKitMac` (macOS).

### Source Files (in `RHVoiceKit/Sources/`)

| Path | Purpose | Key Classes/Functions |
|------|---------|---------------------|
| `RHVoiceKit.h` | Umbrella header — exports RHVoiceEngine and Parameters | Imports `RHVoiceEngine.h`, `RHVoiceEngine+Parameters.h`, `RHVoiceDebugLog.h` |
| `RHVoiceEngine.h` | ObjC interface for the synthesis engine | `RHVoiceEngine` — `synthesize:voice:rate:volume:pitch:`, `synthesizeStreaming:...onChunk:`, `cancel`; `RHVoiceAudioBuffer` — ring-buffer for streaming; `RHVoiceAudioRequestToken` |
| `RHVoiceEngine.mm` | **Core implementation** (~800 lines) — initializes RHVoice C engine, manages synthesis threads, ring buffers, C callbacks | `RHVoiceEngine.init` → `initializeEngine` → `RHVoice_new_tts_engine`; `synthesize:` (sync); `synthesizeStreaming:` (async chunks); C callbacks `play_speech_callback`, `set_sample_rate_callback`; `RHVoiceAudioBuffer` with lock-free SPSC queue |
| `RHVoiceEngine+Parameters.h` | Extended synthesis API with pause duration | `synthesize:voice:rate:volume:pitch:pauseDuration:` |
| `RHVoiceEngine+Parameters.mm` | Implementation of extended parameters | Calls base synthesize with modified params |
| `RHVoice.h` | C API header for the RHVoice TTS engine | `RHVoice_tts_engine`, `RHVoice_init_params`, `RHVoice_callbacks`, `RHVoice_message` |
| `RHVoice_common.h` | Shared C enums | `RHVoice_voice_gender`, `RHVoice_punctuation_mode`, `RHVoice_capitals_mode`, `RHVoice_log_level` |
| `RHVoiceDebugLog.h` | Debug logging C interface | `RHVoiceDebugLogWrite()`, `RHVoiceDebugLogString()` |
| `RHVoiceDebugLog.m` | Logging implementation — writes to App Group shared file | Writes to `group.rhvoice.UkrainianVoices.shared/RHVoiceDebug.log`, auto-truncates at 1MB |

### iOS vs macOS difference

- **iOS (`RHVoiceKit`)**: Links against pre-built static libraries (`libRHVoice.a`, `libRHVoice_core.a`, `libRHVoice_audio.a`)
- **macOS (`RHVoiceKitMac`)**: Compiles the full C++ engine from source:
  - `RHVoice/src/core/` — 58 C++ source files (text processing, phonetics, prosody)
  - `RHVoice/src/lib/` — `lib.cpp` (public C API implementation)
  - `RHVoice/src/hts_engine/` — HTS parametric speech synthesis
  - `RHVoice/src/audio/` — audio output abstraction
  - `RHVoice/external/libs/sonic/` — Sonic pitch/speed library

---

## 4. Shared/ Directory

Located at `UkrainianVoicesApp/Shared/` — compiled into both App and Extension targets.

| Path | Purpose | Key Types |
|------|---------|-----------|
| `RHVoiceSharedSettings.swift` | Voice catalog, settings model, App Group persistence | `RHVoiceSharedSettings` (constants), `RHVoiceVoiceDescriptor`, `RHVoiceSpeechSettings` (rate/volume/speed/pause/pitch), `RHVoicePerVoiceSettings`, `RHVoiceSharedSettingsSnapshot`, `RHVoiceSharedSettingsStore` |
| `RHVoiceSynthesisRuntime.swift` | Synthesis lifecycle state machine | `RHVoiceSynthesisRequest`, `RHVoiceSessionToken`, `RHVoiceSynthesisState` (enum: idle/running/cancelling/completed/cancelled/failed), `RHVoiceRuntimeCoordinator`, `RHVoiceSynthesisRequestFactory` |

### How sharing works

- App Group `group.rhvoice.UkrainianVoices.shared` provides a shared container
- Settings are persisted as JSON (`SharedSettingsSnapshot.json`) in the shared container
- Legacy fallback reads from `UserDefaults(suiteName:)` for backward compatibility
- Extension reads settings at each synthesis request via `RHVoiceSharedSettingsStore.loadSnapshot()`

---

## 5. Data Flow: VoiceOver → Audio Output

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 1. VoiceOver sends AVSpeechSynthesisProviderRequest                     │
│    (contains SSML text + voice identifier)                              │
└────────────────────────────────────┬────────────────────────────────────┘
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 2. UkrainianSpeechSynthesizer.synthesizeSpeechRequest()                 │
│    - Resolves voice identifier → profile name (e.g. "Anatol")           │
│    - Loads settings snapshot from App Group                             │
│    - Extracts SSML rate/volume, applies speedMultiplier                 │
│    - Calls rhvoiceEngine.synthesize(text, voice, rate, volume, pitch)   │
└────────────────────────────────────┬────────────────────────────────────┘
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 3. RHVoiceEngine.synthesize: (ObjC, in RHVoiceEngine.mm)                │
│    - Creates EngineState with ThreadSafeRingBuffer                      │
│    - Calls RHVoice_new_message() with text + voice profile              │
│    - Calls RHVoice_speak() — this invokes the C++ engine                │
└────────────────────────────────────┬────────────────────────────────────┘
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 4. C++ Engine (RHVoice/src/core/ + hts_engine/)                         │
│    - Text normalization → phonetic transcription → prosody              │
│    - HTS parametric synthesis → raw PCM samples (16-bit, 24kHz)         │
│    - Calls play_speech_callback() with chunks of short* samples         │
└────────────────────────────────────┬────────────────────────────────────┘
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 5. play_speech_callback (C function in RHVoiceEngine.mm)                 │
│    - Wraps samples in NSData                                            │
│    - Pushes to ThreadSafeRingBuffer (lock-free SPSC queue)              │
└────────────────────────────────────┬────────────────────────────────────┘
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 6. Back in synthesizeSpeechRequest():                                    │
│    - Collects all chunks into AVAudioPCMBuffer                          │
│    - Converts short→float, stores in outputData array                   │
│    - Sets synthesisComplete = false                                      │
└────────────────────────────────────┬────────────────────────────────────┘
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 7. Audio Render (called by system on real-time audio thread)             │
│    performRender() / internalRenderBlock:                                │
│    - Copies frames from outputData[outputOffset..] to output buffer     │
│    - Advances outputOffset                                              │
│    - When all frames delivered: fade-out + actionFlags = .Complete       │
│    - System delivers audio to VoiceOver → speaker/headphones            │
└─────────────────────────────────────────────────────────────────────────┘
```

### Key design: Synchronous model (like eSpeak)

The extension uses a **synchronous** synthesis model: `synthesizeSpeechRequest()` blocks until all audio is generated, stores it in a flat `[Float]` array, then the render block simply reads from that array. This avoids threading complexity at the cost of initial latency.

---

## 6. Settings & Config Files

### Runtime Settings (user-configurable)

| Setting | Key | Default | Range |
|---------|-----|---------|-------|
| Speech rate | `rate` | 0.5 | 0.1–4.0 |
| Volume | `volume` | 1.0 | 0.0–1.0 |
| Speed multiplier | `speedMultiplier` | 1.0 | 0.2–3.0 |
| Sentence pause | `sentencePause` | 0.0 | 0.0–3.0 |
| Pitch | `pitch` | 1.0 | 0.5–2.0 |
| Enabled voices | `enabledVoiceIdentifiers` | `["com.rhvoice.UkrainianVoices.anatol"]` | — |
| Selected voice | `selectedVoiceIdentifier` | `com.rhvoice.UkrainianVoices.anatol` | — |

### Storage mechanism

1. **Primary**: JSON file `SharedSettingsSnapshot.json` in App Group container
2. **Fallback**: `UserDefaults(suiteName: "group.rhvoice.UkrainianVoices.shared")`
3. **Per-voice overrides**: `perVoiceSettings[identifier].useCustomSettings` flag

### Voice Data Files

Located at `Extension/Resources/RHVoiceData/`:
- `languages/Ukrainian/` — language rules, phonetic data (20+ files)
- `voices/anatol/`, `voices/natalia/`, `voices/marianna/`, `voices/volodymyr/` — HTS model files (16kHz + 24kHz)

Each voice directory contains:
- `voice.info` — metadata (name, language, gender)
- `voice.params` — synthesis parameters
- `16000/` and `24000/` — HTS model trees, PDFs, duration models

### Build-time Config

| File | Purpose |
|------|---------|
| `UkrainianVoicesApp/project.yml` | XcodeGen project definition — all targets, settings, dependencies |
| `Extension/Info-iOS.plist` | iOS extension AudioUnit registration |
| `Extension/Info.plist` | macOS extension AudioUnit registration |
| `App/Info-iOS.plist` | iOS app Info.plist |
| `App/Info.plist` | macOS app Info.plist |
| `App/UkrainianVoices.entitlements` | iOS app entitlements (App Group) |
| `App/UkrainianVoicesMac.entitlements` | macOS app entitlements (App Group + sandbox) |
| `Extension/UkrainianVoicesExtension.entitlements` | iOS extension entitlements |
| `Extension/UkrainianVoicesExtensionMac.entitlements` | macOS extension entitlements |

---

## 7. project.yml Structure (iOS targets)

```yaml
name: UkrainianVoices
options:
  bundleIdPrefix: com.rhvoice
  deploymentTarget:
    iOS: "16.0"

targets:
  # ─── Framework ───
  RHVoiceKit:
    type: framework
    platform: iOS
    sources: ../RHVoiceKit/Sources
    dependencies: [AVFoundation, AVFAudio]
    settings:
      LIBRARY_SEARCH_PATHS: Extension/Libraries
      OTHER_LDFLAGS: -lRHVoice -lRHVoice_core -lRHVoice_audio
      CLANG_CXX_LANGUAGE_STANDARD: c++17

  # ─── Main App ───
  UkrainianVoices:
    type: application
    platform: iOS
    sources: [Shared, App]
    dependencies:
      - target: UkrainianVoicesExtension
      - target: RHVoiceKit (embed: true)
      - AVFoundation, AVFAudio
    postBuildScripts: [Copy RHVoiceData to bundle]
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.rhvoice.ukraine.app.5NNZPP8CRR

  # ─── Speech Extension ───
  UkrainianVoicesExtension:
    type: app-extension
    platform: iOS
    sources: [Shared, Extension/Provider]
    dependencies:
      - target: RHVoiceKit (embed: false)
      - AVFoundation, AVFAudio, AudioToolbox
    postBuildScripts: [Copy RHVoiceData to Extension]
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.rhvoice.ukraine.app.5NNZPP8CRR.Extension
      OTHER_LDFLAGS: -lRHVoice -lRHVoice_core -lRHVoice_audio -lstdc++
```

### Key points:
- Extension links static C++ libs directly (not through framework)
- RHVoiceKit framework is embedded in the app but only linked (not embedded) in the extension
- Voice data is copied via post-build scripts to both app and extension bundles
- Code signing is set to Manual with empty identity (for CI/local unsigned builds)

---

## Appendix: App Target Files

| Path | Purpose | Key Types |
|------|---------|-----------|
| `App/UkrainianVoicesApp.swift` | SwiftUI app entry point, macOS delegate | `UkrainianVoicesApp: App`, `MacAppDelegate` |
| `App/ContentView.swift` | Main UI — voice selection, settings sliders, preview playback (~39KB) | `ContentView: View` |
| `App/RHVoiceSelfTestRunner.swift` | CI self-test — synthesizes all voices, writes log | `RHVoiceSelfTestRunner.runAndExit()` |
| `App/LogCollector.swift` | In-app log collection for debugging (iOS: email, macOS: stub) | `LogCollector`, `MailView` |
| `App/Info-iOS.plist` | iOS app metadata | — |
| `App/Info.plist` | macOS app metadata | — |
| `App/Assets.xcassets/` | App icons | — |

## Appendix: Extension Bridge Files (legacy, not in active targets)

Located at `Extension/Bridge/` — these are **duplicates** of RHVoiceKit headers, kept for historical/reference purposes. The active project.yml targets do NOT include `Extension/Bridge/` in their sources.

| Path | Purpose |
|------|---------|
| `Bridge/RHVoiceEngine.h` | Copy of RHVoiceKit header |
| `Bridge/RHVoiceEngine+Parameters.h` | Copy of parameters header |
| `Bridge/RHVoiceEngine+Parameters.mm` | Copy of parameters implementation |
| `Bridge/RHVoice.h` | Copy of C API header |
| `Bridge/RHVoice_common.h` | Copy of common enums |
| `Bridge/UkrainianVoices-Bridging-Header.h` | ObjC bridging header (imports RHVoiceEngine.h) |

## Appendix: Test Files

| Path | Purpose |
|------|---------|
| `Tests/UkrainianSpeechSynthesizerTests.swift` | Unit tests for synthesizer |
| `Tests/RHVoiceParametersTests.swift` | Unit tests for parameter handling |
