# Piper TTS iOS App — Speech Synthesis Extension Analysis

Source: `~/Projects/piper-app` (https://github.com/IhorShevchuk/piper-app)
Build system: Tuist (Project.swift manifest)

---

## 1. REGISTRATION (Info.plist)

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionAttributes</key>
    <dict>
        <key>AudioComponents</key>
        <array>
            <dict>
                <key>type</key>         <string>ausp</string>
                <key>subtype</key>      <string>pipr</string>
                <key>manufacturer</key> <string>pipr</string>
                <key>tags</key>         <array><string>Speech Synthesizer</string></array>
                <key>description</key>  <string>pipertts</string>
                <key>name</key>         <string>piper: pipertts</string>
                <key>sandboxSafe</key>  <true/>
                <key>version</key>      <integer>67072</integer>
            </dict>
        </array>
    </dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.AudioUnit</string>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).AudioUnitFactory</string>
</dict>
```

Key points:
- `type` = `ausp` — `kAudioUnitType_SpeechSynthesizer`
- `subtype` and `manufacturer` are both `pipr` (4-char OSType codes)
- `tags` = `["Speech Synthesizer"]` — this is what makes iOS register it as a SSML voice provider
- `sandboxSafe` = true — required for out-of-process hosting
- `NSExtensionPointIdentifier` = `com.apple.AudioUnit` (NOT `com.apple.speech-synthesis`)
- `NSExtensionPrincipalClass` = `PiperTTS.AudioUnitFactory` (AUAudioUnitFactory conformance)

---

## 2. ENTITLEMENTS

Extension entitlements (from Project.swift):
```swift
let extensionEntitlements: [String: Plist.Value] = [
    "com.apple.security.application-groups": .array([.string("group.pipertts.data")]),
    "inter-app-audio": .boolean(true)
]
```

App entitlements:
```swift
let appEntitlements: [String: Plist.Value] = [
    "com.apple.security.app-sandbox": .boolean(true),
    "com.apple.security.application-groups": .array([.string("group.pipertts.data")]),
    "inter-app-audio": .boolean(true),
    "com.apple.security.network.client": .boolean(true)
]
```

Key points:
- Shared app group `group.pipertts.data` — used to share model files between app and extension
- `inter-app-audio` — required for AU extensions
- Extension does NOT have `app-sandbox` key (inherits from extension hosting)
- Extension does NOT need `network.client` (only the app downloads models)

---

## 3. BUNDLE STRUCTURE

```
Piper.app
├── PiperApp (main app target)
│   └── depends on: PiperAppUtils, PiperTTS
├── PiperTTS.appex (extension target, product: .appExtension)
│   └── depends on: PiperAppUtils, piper-objc, espeak-ng-data, libc++
└── PiperAppUtils (product: .staticFramework)
    └── shared code: ModelInfo, FileManager, Logger, Voice utils, Constants
```

- **PiperAppUtils** is a `.staticFramework` — linked into both app and extension
- **piper-objc** (external SPM package) — Objective-C++ wrapper around piper C++ engine
- **espeak-ng-data** (external SPM package) — phonemization data for espeak-ng
- **libc++** — linked as `.sdk(name: "c++", type: .library)` for C++ runtime
- Extension loaded **out-of-process** (`.loadOutOfProcess` option in host app)
- Model files stored in shared app group container, accessed by both targets

---

## 4. AUDIO STREAM — Buffer Management & Delivery

### Architecture: Offline rendering (NOT real-time streaming)

The extension uses `AVSpeechSynthesisProviderAudioUnit` which processes **offline** — the system pulls audio via `internalRenderBlock` at its own pace.

### Flow:

1. **`synthesizeSpeechRequest(_:)`** — system calls this with SSML text
2. Piper engine starts synthesis on its own thread, delivers samples via `PiperDelegate.piperDidReceiveSamples(_:withSize:)`
3. Samples accumulated in `outputData: [Float]` array (lock-protected with `os_unfair_lock`)
4. System calls render block repeatedly requesting `frameCount` frames
5. Render block copies from `outputData` at current `outputOffset`

### Buffer management:

```swift
private var outputData: [Float] = []      // all synthesized samples
private var outputOffset = 0              // read cursor
private var outputDataLock = os_unfair_lock_s()  // thread safety
```

### Completion signaling:

- Render block checks `piper.completed()` — when true AND no more data → sets `actionFlags.pointee = .offlineUnitRenderAction_Complete`
- Also completes if `request == nil` (cancelled)

### Pre-buffer / wait strategy:

When render is called but data isn't ready yet:
- **Recursive retry** up to `outputRecurseCallNumberMax = 200` times
- Uses `pauseUntil(maxDelayFactor:or:)` — spins RunLoop with `baseDelayMicroseconds = 500` (total max ~100ms wait)
- Checks `piper.completed()` as exit condition
- If retries exhausted, returns whatever data is available

### Resampling:

If model sample rate ≠ output format (22050 Hz default), uses **vDSP_vlint** (linear interpolation) for real-time upsampling in the delegate callback.

---

## 5. PARAMETERS — Rate/Pitch/Volume Handling

### Current implementation: **NONE**

- No `AUParameter` tree defined
- No `parameterTree` override
- No rate/pitch/volume handling whatsoever
- The SSML is passed directly to piper: `piper?.synthesizeSSML(speechRequest.ssmlRepresentation, speakerId:...)`
- Piper engine handles SSML internally (prosody tags if supported by the model)

### SSML:

- `AVSpeechSynthesisProviderRequest.ssmlRepresentation` is passed as-is to piper-objc
- The host app wraps text in `<speak>...</speak>` tags
- No custom SSML parsing in the extension

---

## 6. CANCEL — cancelSpeechRequest

```swift
public override func cancelSpeechRequest() {
    cleanUp()
}

func cleanUp() {
    request = nil
    piper?.cancel()
    os_unfair_lock_lock(&outputDataLock)
    outputData = []
    outputOffset = 0
    os_unfair_lock_unlock(&outputDataLock)
}
```

- Sets `request = nil` — render block will see this and return `.offlineUnitRenderAction_Complete`
- Calls `piper?.cancel()` — stops the C++ engine
- Clears buffer and resets offset under lock
- Simple and immediate — no graceful fade-out

---

## 7. VOICE REGISTRATION

### speechVoices property:

```swift
public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
    get { return AVSpeechSynthesisProviderVoice.supportedVoices }
    set { }
}
```

### Dynamic voice list from installed models:

```swift
public static var supportedVoices: [AVSpeechSynthesisProviderVoice] {
    let installedModels = ModelInfo.installedModels
    return installedModels.flatMap { model in
        let languageCode = "\(model.language.family)-\(model.language.region)"  // e.g. "en-US"
        
        if model.numberOfSpeakers <= 1 {
            return [AVSpeechSynthesisProviderVoice(
                name: model.name.capitalized,
                identifier: model.voiceId,
                primaryLanguages: [languageCode],
                supportedLanguages: [languageCode]
            )]
        }
        // Multi-speaker: one voice per speaker
        return model.speakers.map { (name, id) in
            AVSpeechSynthesisProviderVoice(
                name: name.capitalized,
                identifier: "\(model.voiceId)\(Constants.speakerIdSeparator)\(id)",
                primaryLanguages: [languageCode],
                supportedLanguages: [languageCode]
            )
        }
    }
}
```

### Voice identifier format:

```
{dataset}>{quality}>{sampleRate}>{languageCode}>{numSpeakers}
// separator is ">0<"
// multi-speaker appends: <+>{speakerId}
```

### Key points:
- **Fully dynamic** — voices come from installed model JSON files in shared app group
- Language codes from model metadata: `family`-`region` (BCP-47 format)
- Multi-speaker models register one voice per speaker
- Speaker ID extracted from identifier suffix for synthesis
- No hardcoded voice list — user installs models via the app

---

## 8. CLEVER TRICKS

### 1. Shared App Group for model storage
Models downloaded by the app are stored in the shared container. Extension reads them directly — no IPC needed for model data.

### 2. Message Channel for state queries
Uses `AUMessageChannel` to let the host app query whether synthesis is running (`isSyntehizerRunning`). This avoids polling the audio buffer.

### 3. Recursive render with backoff
Instead of returning silence when data isn't ready, the render block recursively calls itself up to 200 times with RunLoop spinning. This ensures the system gets actual audio data rather than gaps.

### 4. vDSP linear interpolation for resampling
Uses Accelerate framework (`vDSP_vlint`) for efficient sample rate conversion when model output doesn't match the 22050 Hz default format. Done in the delegate callback so render block always gets correctly-sampled data.

### 5. Lazy Piper initialization with caching
`createPiperIfNeeded` only creates a new Piper instance if the model changed. Reuses the existing instance for same-voice requests — avoids expensive model reload.

### 6. Out-of-process loading
Host app uses `.loadOutOfProcess` — extension crashes don't take down the app. Health check timer (3s interval) detects disconnection and auto-reconnects.

### 7. Cancel before re-synthesize
In `synthesizeSpeechRequest`, calls `piper?.cancel()` before starting new synthesis — prevents stale data from previous request leaking into new output.

### 8. No AUParameter overhead
Deliberately skips rate/pitch/volume parameters. Piper models have fixed prosody, so there's nothing to parameterize. Keeps the implementation minimal.

### 9. Static framework for shared code
`PiperAppUtils` as `.staticFramework` means no dynamic linking overhead and no framework embedding issues between app and extension.

### 10. Privacy-conscious logging
Uses `%{private}@` in release builds (os_log) — synthesized text never appears in device logs unless explicitly enabled in debug.

---

## Summary for RHVoice Implementation

Key takeaways for building a similar extension:
1. Use `com.apple.AudioUnit` extension point with `ausp` type and `"Speech Synthesizer"` tag
2. Subclass `AVSpeechSynthesisProviderAudioUnit` — implement `synthesizeSpeechRequest`, `cancelSpeechRequest`, `speechVoices`, `internalRenderBlock`
3. Use shared app group for voice data files
4. Buffer all audio in memory, serve via render block, signal completion with `.offlineUnitRenderAction_Complete`
5. Handle the case where synthesis is slower than render requests (wait/retry strategy)
6. Voice identifiers must encode enough info to locate the correct model at synthesis time
