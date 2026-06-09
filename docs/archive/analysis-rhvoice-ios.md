# RHVoice iOS Extension — Technical Analysis

## 1. REGISTRATION (Info-iOS.plist)

**File:** `UkrainianVoicesApp/Extension/Info-iOS.plist`

| Key | Value |
|-----|-------|
| CFBundleDevelopmentRegion | `$(DEVELOPMENT_LANGUAGE)` |
| CFBundleDisplayName | `Ukrainian Voices` |
| CFBundleExecutable | `$(EXECUTABLE_NAME)` |
| CFBundleIdentifier | `$(PRODUCT_BUNDLE_IDENTIFIER)` |
| CFBundlePackageType | `XPC!` |
| CFBundleShortVersionString | `1.0` |
| CFBundleVersion | `1` |
| **NSExtensionPointIdentifier** | `com.apple.AudioUnit` |
| **NSExtensionPrincipalClass** | `$(PRODUCT_MODULE_NAME).AudioUnitFactory` |

**AudioComponents** (single entry):

| Key | Value |
|-----|-------|
| description | `RHVoice Ukrainian Speech Synthesizer` |
| manufacturer | `RHVo` (4-char code) |
| name | `RHVo: RHVoice Ukrainian Speech Synthesizer` |
| sandboxSafe | `true` |
| subtype | `rhvc` (4-char code) |
| tags | `["Synthesizer", "Speech"]` |
| type | `ausp` (Audio Unit Speech Synthesizer) |
| version | `67072` (0x10600 = v1.6.0) |

**Resolved in built archive:**
- NSExtensionPrincipalClass → `UkrainianVoicesExtension.AudioUnitFactory`
- CFBundleIdentifier → `com.rhvoice.ukraine.app.5NNZPP8CRR.Extension`

---

## 2. ENTITLEMENTS

**File:** `UkrainianVoicesApp/Extension/UkrainianVoicesExtension.entitlements`

```xml
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.rhvoice.UkrainianVoices.shared</string>
    </array>
</dict>
```

Only entitlement: **App Group** for shared settings between host app and extension.

No sandbox, no network, no file access entitlements — minimal footprint.

---

## 3. BUNDLE STRUCTURE

### project.yml — iOS Extension Target (`UkrainianVoicesExtension`)

- **Type:** `app-extension`
- **Platform:** `iOS`
- **Deployment target:** `16.0`
- **Sources:** `Shared/` + `Extension/Provider/`
- **Bundle ID:** `com.rhvoice.ukraine.app.5NNZPP8CRR.Extension`

**Dependencies:**
| Dependency | Embed |
|-----------|-------|
| `RHVoiceKit` (framework target) | `false` — NOT embedded in appex |
| `AVFoundation.framework` | SDK |
| `AVFAudio.framework` | SDK |
| `AudioToolbox.framework` | SDK |

**Static linking:**
```yaml
LIBRARY_SEARCH_PATHS: "$(SRCROOT)/Extension/Libraries"
OTHER_LDFLAGS: "-lRHVoice -lRHVoice_core -lRHVoice_audio -lstdc++"
```

The extension statically links `libRHVoice.a`, `libRHVoice_core.a`, `libRHVoice_audio.a` (pre-built C++ static libs).

**Host app (`UkrainianVoices`):**
- Embeds `RHVoiceKit.framework` (embed: true)
- Depends on `UkrainianVoicesExtension` (auto-embeds in PlugIns/)

### Actual Archive Structure

```
UkrainianVoices.app/
├── UkrainianVoices (main binary)
├── RHVoiceData/                    ← voice data in main app too
│   ├── languages/Ukrainian/
│   └── voices/{marianna,natalia,anatol,volodymyr}/
├── Frameworks/
│   └── RHVoiceKit.framework/
│       └── RHVoiceKit (2.3 MB dylib, arm64)
├── PlugIns/
│   └── UkrainianVoicesExtension.appex/
│       ├── UkrainianVoicesExtension (152 KB binary, arm64)
│       ├── Info.plist
│       └── RHVoiceData/            ← voice data duplicated in extension
│           ├── languages/Ukrainian/
│           └── voices/{marianna,natalia,anatol,volodymyr}/
└── ContentView.swift.bak_codex_20260327
```

**Key observations:**
- Extension binary is only 152 KB — static libs are linked into it
- RHVoiceKit.framework (2.3 MB) is in the app's Frameworks/ but NOT in the appex
- Voice data (RHVoiceData/) is duplicated: once in app root, once in appex (total appex = 72 MB)
- No Frameworks/ directory inside the appex — pure static linking for the extension
- The extension does NOT embed RHVoiceKit; it links the static `.a` files directly

---

## 4. AUDIO STREAM (iOS Path)

The `#if os(iOS)` path uses a **streaming model** with a lock-free SPSC ring buffer:

### Architecture

```
synthesizeSpeechRequest() → synthesisQueue.async {
    rhvoiceEngine.synthesizeStreaming(text, voice, rate, volume, pitch) { samples, count, sampleRate in
        audioBuffer.appendSamples(samples, count, token)
    }
    audioBuffer.markCompleted(with: token)
}
```

### Flow:
1. `synthesizeSpeechRequest()` is called by the system
2. Creates a new `RHVoiceAudioRequestToken` via `audioBuffer.beginRequest()`
3. Dispatches synthesis to `synthesisQueue` (`.userInitiated` QoS)
4. `RHVoiceEngine.synthesizeStreaming()` calls the chunk callback with `short*` PCM samples as they're generated
5. Chunks are appended to `RHVoiceAudioBuffer` (Obj-C ring buffer class)
6. When synthesis completes, `audioBuffer.markCompleted(with: token)` signals end

### Render Block (iOS):
```swift
audioBuffer.renderFrames(frames, maxFrames: requestedFrames, preBufferFrames: 2400, didComplete: &didComplete)
```

- Pre-buffers 2400 frames (100ms at 24kHz) before starting playback
- Returns `.offlineUnitRenderAction_Complete` when done
- Returns `.offlineUnitRenderAction_Render` while streaming

### Audio Format:
- Sample rate: **24000 Hz**
- Format: **Float32, non-interleaved, linear PCM**
- Channels: **1 (mono)**

---

## 5. PARAMETERS (Rate/Pitch/Volume)

### Source of parameters:
1. **SSML parsing** — extracts `rate="X%"` and `volume="XdB"` from the SSML text
2. **Shared settings** — loaded from App Group (`RHVoiceSharedSettingsStore.loadSnapshot()`)
3. **Per-voice overrides** — if `useCustomSettings` is true for a voice

### Rate:
```
ssmlRate = extractSSMLRate(from: ssml)  // percentage/100, default 1.0
mappedRate = ssmlRate <= 2.0 ? ssmlRate : 2.0 + log(ssmlRate / 2.0) * 1.5  // log curve above 2x
effectiveRate = mappedRate × settings.speedMultiplier
cappedRate = min(effectiveRate, 4.0)  // hard cap at 4x
```

### Volume:
```
ssmlVolume = extractSSMLVolume(from: ssml)  // dB → linear, clamped [0.1, 2.0]
effectiveVolume = ssmlVolume × settings.volume
```

### Pitch:
- Passed directly from `settings.pitch` (default 1.0)
- No SSML extraction for pitch

### Default settings (`RHVoiceSpeechSettings.recommended`):
- rate: 0.5
- volume: 1.0
- speedMultiplier: 1.0
- sentencePause: 0.0
- pitch: 1.0

---

## 6. CANCEL

### iOS cancel path:
```swift
public override func cancelSpeechRequest() {
    rhvoiceEngine.cancel()              // Signals C++ engine to stop
    audioBuffer.cancelCurrentRequest()  // Invalidates ring buffer token
    currentToken = nil                  // Drops reference
}
```

Three-pronged cancellation:
1. **Engine-level:** `rhvoiceEngine.cancel()` — stops the C++ synthesis loop
2. **Buffer-level:** `audioBuffer.cancelCurrentRequest()` — discards buffered audio, unblocks render
3. **Token-level:** `currentToken = nil` — any in-flight `appendSamples` calls with old token are rejected

---

## 7. VOICE REGISTRATION

### `speechVoices` property:

```swift
private static let staticVoices: [AVSpeechSynthesisProviderVoice] = [
    AVSpeechSynthesisProviderVoice(name: "Anatol",    identifier: "com.rhvoice.UkrainianVoices.anatol",    primaryLanguages: ["uk-UA"], supportedLanguages: ["uk-UA"]),
    AVSpeechSynthesisProviderVoice(name: "Natalia",   identifier: "com.rhvoice.UkrainianVoices.natalia",   primaryLanguages: ["uk-UA"], supportedLanguages: ["uk-UA"]),
    AVSpeechSynthesisProviderVoice(name: "Marianna",  identifier: "com.rhvoice.UkrainianVoices.marianna",  primaryLanguages: ["uk-UA"], supportedLanguages: ["uk-UA"]),
    AVSpeechSynthesisProviderVoice(name: "Volodymyr", identifier: "com.rhvoice.UkrainianVoices.volodymyr", primaryLanguages: ["uk-UA"], supportedLanguages: ["uk-UA"]),
]
```

**Dynamic filtering:** The getter filters by `enabledVoiceIdentifiers` from shared settings. If no voices are enabled, returns all 4.

| Voice | Identifier | Language |
|-------|-----------|----------|
| Anatol | `com.rhvoice.UkrainianVoices.anatol` | uk-UA |
| Natalia | `com.rhvoice.UkrainianVoices.natalia` | uk-UA |
| Marianna | `com.rhvoice.UkrainianVoices.marianna` | uk-UA |
| Volodymyr | `com.rhvoice.UkrainianVoices.volodymyr` | uk-UA |

Voice data directories in bundle: `RHVoiceData/voices/{anatol,natalia,marianna,volodymyr}/`

---

## 8. MAIN APP Info.plist (Info-iOS.plist)

**File:** `UkrainianVoicesApp/App/Info-iOS.plist`

```xml
CFBundleDevelopmentRegion: uk
CFBundleDisplayName: Українські голоси
LSRequiresIPhoneOS: true
UIApplicationSceneManifest: { UIApplicationSupportsMultipleScenes: true }
UILaunchScreen: {}
UISupportedInterfaceOrientations: [Portrait, LandscapeLeft, LandscapeRight]
```

**NO speech-related keys.** No `AudioComponentBundle`, no `AudioComponents`, no `NSExtension` — it's a plain SwiftUI app shell.

Main app entitlements (`UkrainianVoices.entitlements`):
```xml
com.apple.security.application-groups: ["group.rhvoice.UkrainianVoices.shared"]
```

Same App Group as the extension — used for shared settings only.

---

## 9. HOST APP REGISTRATION

**The main app does NOT register the AudioUnit.** There is no `AudioComponents` array or `AudioComponentBundle` key in the host app's Info.plist.

On iOS, this is **correct behavior**:
- The `com.apple.AudioUnit` extension point is self-registering — iOS discovers it from the `.appex` bundle's Info.plist
- The host app only needs to embed the extension in `PlugIns/` (which it does)
- No additional declaration in the host app is required for `AVSpeechSynthesisProviderAudioUnit` extensions

The host app's role is:
1. Provide the container for the extension (PlugIns/ directory)
2. Share settings via App Group
3. Offer a UI for voice management/preview

---

## Summary

| Aspect | Implementation |
|--------|---------------|
| Extension type | `com.apple.AudioUnit` (AudioUnit Speech Provider) |
| Base class | `AVSpeechSynthesisProviderAudioUnit` |
| Factory | `AudioUnitFactory` (AUAudioUnitFactory protocol) |
| Audio delivery | Streaming ring buffer (iOS) / Synchronous array (macOS) |
| Linking | Static `.a` libs (RHVoice C++ engine) |
| Framework | RHVoiceKit embedded in app, NOT in extension |
| Voice data | Copied via post-build script into appex bundle |
| Settings | App Group shared JSON snapshot |
| Cancel | Engine cancel + buffer invalidation + token drop |
| Voices | 4 Ukrainian voices, uk-UA language |
| Sample rate | 24000 Hz, Float32 mono |
| Min iOS | 16.0 |
