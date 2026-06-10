# Analysis: eSpeak-NG iOS Speech Synthesis App

**Repository:** https://github.com/espeak-ng/espeak-ng-ios-app  
**Author:** Yury Popov (@djphoenix), 2022  
**License:** Extension = GPLv3 (links libespeak-ng), Application = MIT  
**Cloned to:** ~/tmp-espeak-ios

---

## 1. REGISTRATION (Extension/Info.plist)

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionAttributes</key>
    <dict>
        <key>AudioComponents</key>
        <array>
            <dict>
                <key>description</key>    <string>Synth</string>
                <key>manufacturer</key>   <string>ESPK</string>
                <key>name</key>           <string>eSpeak-NG</string>
                <key>sandboxSafe</key>    <true/>
                <key>subtype</key>        <string>espk</string>
                <key>tags</key>           <array><string>Speech Synthesizer</string></array>
                <key>type</key>           <string>ausp</string>
                <key>version</key>        <integer>67072</integer>
            </dict>
        </array>
    </dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.AudioUnit</string>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).AudioUnitFactory</string>
</dict>
```

Key observations:
- **type** = `ausp` (Audio Unit Speech Synthesizer — the magic type for speech synth extensions)
- **subtype** = `espk` (4-char code, unique to this synth)
- **manufacturer** = `ESPK` (4-char code, unique to developer)
- **tags** = `["Speech Synthesizer"]` — required for VoiceOver discovery
- **sandboxSafe** = true — required for out-of-process hosting
- **NSExtensionPointIdentifier** = `com.apple.AudioUnit` (NOT a custom extension point)
- **NSExtensionPrincipalClass** = `$(PRODUCT_MODULE_NAME).AudioUnitFactory` — the factory class

The `AudioUnitFactory` class is minimal:
```swift
public class AudioUnitFactory: NSObject, AUAudioUnitFactory {
    public func beginRequest(with context: NSExtensionContext) {}
    @objc public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        return try SynthAudioUnit(componentDescription: componentDescription, options: [])
    }
}
```

---

## 2. ENTITLEMENTS

**App (Project/App.entitlements):**
```xml
<key>com.apple.security.app-sandbox</key>       <true/>
<key>com.apple.security.files.user-selected.read-only</key> <true/>
<key>inter-app-audio</key>                      <true/>
```

**Extension (Project/Ext.entitlements):**
```xml
<key>com.apple.security.app-sandbox</key>       <true/>
```

Key observations:
- Extension has **only** app-sandbox — minimal entitlements
- No app groups! Communication is via AUMessageChannel (XPC), not shared UserDefaults
- App has `inter-app-audio` for instantiating the AU out-of-process
- No network entitlement — everything is local

---

## 3. BUNDLE STRUCTURE

```
EspeakNg.app                          (host application)
├── Application/                      (SwiftUI app, MIT license)
└── PlugIns/
    └── Synth.appex                   (extension, GPLv3)
        └── links: libespeak-ng (static via SPM)
                   espeak-ng-data (bundled resource via SPM)
```

- **Two targets:** `EspeakNg` (app) and `Synth` (extension, product type `com.apple.product-type.app-extension`)
- Extension is embedded via "Embed Foundation Extensions" copy phase
- **No shared framework** — the app does NOT link libespeak-ng at all
- Extension links `libespeak-ng` and `espeak-ng-data` as **Swift Package Manager** dependencies from `https://github.com/espeak-ng/espeak-ng-spm.git`
- The SPM package provides a static library (`libespeak-ng`) and a resource bundle (`espeak-ng-data`)
- App communicates with extension via `AVAudioUnit.instantiate(options: .loadOutOfProcess)` + `AUMessageChannel`
- Bundle IDs: app = `dj.phoenix.espeak-ng`, extension = `dj.phoenix.espeak-ng.synth-ext`
- Deployment target: iOS 16.0, macOS 13.0

---

## 4. AUDIO STREAM: Synchronous Pre-render Strategy

**This is the most important architectural decision: they synthesize ALL audio upfront, then stream it from a buffer.**

### Synthesis (in `synthesizeSpeechRequest`):
```swift
public override func synthesizeSpeechRequest(_ speechRequest: AVSpeechSynthesisProviderRequest) {
    // 1. Parse voice identifier from request
    // 2. Set espeak voice
    // 3. Synthesize ENTIRE text synchronously into SynthHolder.samples (Int16[])
    espeak_ng_Synthesize(text, text.count, 0, POS_CHARACTER, 0,
                         UInt32(espeakSSML | espeakCHARS_UTF8), nil, ptr)
    espeak_ng_Synchronize()  // blocks until complete
    
    // 4. Convert Int16 → Float32 using vDSP
    let resampled = vDSP.multiply(Float(1.0/32767.0),
        vDSP.integerToFloatingPoint(holder.samples, floatingPointType: Float.self))
    
    // 5. Store in output buffer
    self.output = resampled
    self.outputOffset = 0
}
```

### Render block (in `performRender`):
```swift
private func performRender(...) -> AUAudioUnitStatus {
    // Zero the output buffer
    frames.assign(repeating: 0, count: Int(frameCount))
    
    // Copy from pre-rendered buffer
    let count = min(self.output.count - self.outputOffset, Int(frameCount))
    frames.assign(from: ptr.baseAddress!.advanced(by: self.outputOffset), count: count)
    outputAudioBufferList.pointee.mBuffers.mDataByteSize = UInt32(count * MemoryLayout<Float32>.size)
    
    // Advance position
    self.outputOffset += count
    
    // Signal completion when buffer exhausted
    if self.outputOffset >= self.output.count {
        actionFlags.pointee = .offlineUnitRenderAction_Complete
        self.output.removeAll()
        self.outputOffset = 0
    }
    return noErr
}
```

### Audio format:
```swift
AudioStreamBasicDescription(
    mSampleRate: 22050.0,
    mFormatID: kAudioFormatLinearPCM,
    mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
    mBytesPerPacket: 4,
    mFramesPerPacket: 1,
    mBytesPerFrame: 4,
    mChannelsPerFrame: 1,
    mBitsPerChannel: 32,
    mReserved: 0
)
```
- 22050 Hz, mono, 32-bit float, non-interleaved

### Thread safety:
- Uses `DispatchSemaphore(value: 1)` as a mutex to protect `output` and `outputOffset`
- Both `synthesizeSpeechRequest` and `performRender` acquire the semaphore

### Completion signaling:
- Sets `actionFlags.pointee = .offlineUnitRenderAction_Complete` when all samples delivered
- Also sets `mDataByteSize` to actual bytes written (may be less than frameCount on last call)

---

## 5. PARAMETERS: Rate/Pitch/Volume Handling

**They do NOT use VoiceOver's rate/pitch/volume from the speech request.** Instead, they expose custom AUParameters that the user configures in the app.

### Parameter tree:
```swift
enum EspeakParameter: AUParameterAddress {
    case rate, volume, pitch, wordGap, range, ssml_breaks
}
```

| Parameter | Range | Unit | eSpeak mapping |
|-----------|-------|------|----------------|
| rate | espeakRATE_MINIMUM..900 | BPM (words/min) | espeakRATE |
| volume | 0..200 | percent | espeakVOLUME |
| pitch | 0..100 | percent | espeakPITCH |
| wordGap | 0..500 | milliseconds | espeakWORDGAP |
| range | 0..100 | percent | espeakRANGE |
| ssml_breaks | 0..200 | percent | espeakSSML_BREAK_MUL |

### SSML handling:
- The request's `ssmlRepresentation` is passed directly to espeak with `espeakSSML` flag
- They also pass `espeakCHARS_UTF8`
- The `ssml_breaks` parameter multiplies SSML `<break>` durations

### Settings persistence:
- Parameters are stored in a JSON file in the extension's documents directory (`settings.json`)
- Uses a custom `@JSONFileBacked` property wrapper
- Settings are applied before each synthesis via `container.setParams()`

### Important note:
VoiceOver sends rate/pitch/volume in the SSML (as prosody tags), but eSpeak handles those via its own SSML parser. The AUParameters here are **additional** user-configurable overrides on top of what VoiceOver sends.

---

## 6. CANCEL: cancelSpeechRequest

```swift
public override func cancelSpeechRequest() {
    self.outputMutex.wait()
    self.output.removeAll()
    self.outputOffset = 0
    log.info("stop synthesizing")
    self.outputMutex.signal()
}
```

Simple approach:
- Acquire mutex
- Clear the output buffer
- Reset offset to 0
- Release mutex

The render block will then find an empty buffer and signal completion. Since eSpeak synthesis is synchronous and fast, there's no need to interrupt an in-progress synthesis — it's already done by the time cancel could be called.

---

## 7. VOICE REGISTRATION: speechVoices Property

```swift
public override var speechVoices: [AVSpeechSynthesisProviderVoice] {
    get {
        // For each exposed locale × each voice variant:
        for langVar in langVariants.filter({ exposed.contains($0.universalId) }) {
            let langId = langVar.universalId  // e.g., "uk-UA"
            let langPath = "auto.\(langId.lowercased())"
            
            // Default voice (no variant)
            list.append(AVSpeechSynthesisProviderVoice(
                name: "ESpeak",
                identifier: "\(langPath).\(emptyVoiceId)",  // "auto.uk-ua.__espeak"
                primaryLanguages: [langId],
                supportedLanguages: [langId]
            ))
            
            // Each voice variant (male/female variants)
            for voice in voices {
                let v = AVSpeechSynthesisProviderVoice(
                    name: voice.name,
                    identifier: "\(langPath).\(voice.identifier)",
                    primaryLanguages: [langId],
                    supportedLanguages: [langId]
                )
                v.gender = ...  // .male, .female, .unspecified
                v.age = Int(voice.age)
                list.append(v)
            }
        }
    }
}
```

### Voice identifier format:
`auto.<locale>.<voice_variant>` — e.g., `auto.en-us.f3` or `auto.uk-ua.__espeak`

### Language matching (in synthesizeSpeechRequest):
```swift
// Parse identifier: "auto.uk-ua.f3" → parts = ["auto", "uk-ua", "f3"]
if parts[0] == "auto" {
    // Match locale to espeak language
    let espeakLang = matchLang(container.langs, Locale.Language(identifier: String(parts[1])))
}
// Combine: "uk/f3" or just "uk" if default voice
let full_voice_id = [lang_id, voice_id].joined(separator: "+")
espeak_ng_SetVoiceByName(full_voice_id)
```

### Exposed locales:
- User selects which languages to expose in the app UI
- Stored in `exposed.json` in documents directory
- Default: user's preferred languages + en-US
- Uses `Locale.Language.systemLanguages` + `Locale.availableIdentifiers` to enumerate all possible locales

### Language code format:
Uses BCP-47 style: `languageCode-REGION` (e.g., `en-US`, `uk-UA`, `de-DE`)

---

## 8. CLEVER TRICKS Worth Copying

### 1. AUMessageChannel for app↔extension communication
Instead of App Groups/UserDefaults, they use `AUMessageChannel` (XPC-based):
```swift
public override func messageChannel(for channelName: String) -> AUMessageChannel {
    class MC: AUMessageChannel {
        func callAudioUnit(_ message: [AnyHashable : Any]) -> [AnyHashable : Any] {
            // Handle messages from host app
            if message["initHost"] as? Bool == true {
                // Return voice lists, exposed locales
            }
            if let expose = message["expose"] as? [String] {
                // Update exposed locales
            }
        }
    }
    return MC()
}
```
This avoids App Groups entirely and keeps the extension self-contained.

### 2. Singleton pattern for espeak initialization
```swift
static private let _single = EspeakContainer()
static var single: EspeakContainer {
    if Thread.isMainThread { return _single }
    return DispatchQueue.main.sync { return _single }
}
```
Ensures espeak is initialized exactly once, thread-safely.

### 3. Voice caching to avoid re-initialization
```swift
private static var espeakVoice = ""
// In synthesizeSpeechRequest:
if Self.espeakVoice != full_voice_id {
    try espeak_ng_SetVoiceByName(full_voice_id).check()
    Self.espeakVoice = full_voice_id
}
```
Only switches voice when it actually changes.

### 4. vDSP for Int16→Float32 conversion
```swift
let resampled = vDSP.multiply(Float(1.0/32767.0),
    vDSP.integerToFloatingPoint(holder.samples, floatingPointType: Float.self))
```
Uses Accelerate framework for SIMD-optimized conversion.

### 5. Data bundle installation to documents
```swift
try EspeakLib.ensureBundleInstalled(inRoot: root)
espeak_ng_InitializePath(root.path)
```
Copies espeak data to documents directory on first launch — allows the extension to access it without app group containers.

### 6. OSSignposter for performance profiling
```swift
let sp = OSSignposter(logger: log)
try sp.withIntervalSignpost("espeak_bundle") { ... }
try sp.withIntervalSignpost("espeak_init") { ... }
```
Built-in Instruments profiling support.

### 7. Synchronous synthesis mode
Uses `ENOUTPUT_MODE_SYNCHRONOUS` — espeak generates all audio in one blocking call via callback. This is simpler than streaming and works because espeak is fast enough.

### 8. Dual licensing via architectural separation
App (MIT) communicates with Extension (GPLv3) only via XPC/AudioUnit protocol — no code sharing, no linking. This lets the app code be reused with other engines.

### 9. No App Groups needed
The extension stores its own settings in its own documents directory. The app communicates via AUMessageChannel. This simplifies provisioning.

### 10. Locale matching with fallback
```swift
func matchLang(_ langs: [_Voice], _ locale: Locale.Language) -> _Voice? {
    let lidx = Set<String>([
        locale.universalId,
        locale.minimalIdentifier,
        locale.maximalIdentifier,
        locale.languageCode?.identifier(.alpha2),
        locale.languageCode?.identifier(.alpha3),
    ].compactMap({ $0?.lowercased() }))
    // Find best match by priority
}
```
Tries multiple identifier formats to find the best espeak voice for a given locale.

---

## Summary for RHVoice Implementation

| Aspect | eSpeak approach | Recommendation for RHVoice |
|--------|----------------|---------------------------|
| Synthesis | Synchronous, pre-render all | Same — RHVoice is fast enough |
| Audio format | 22050 Hz Float32 mono | Match RHVoice native sample rate |
| Thread safety | DispatchSemaphore mutex | Same pattern |
| Completion | `.offlineUnitRenderAction_Complete` | Same |
| Cancel | Clear buffer + reset offset | Same |
| Voice registration | Dynamic from engine's voice list | Same — enumerate RHVoice voices |
| Parameters | Custom AUParameters for engine settings | Consider exposing rate/pitch/volume |
| App↔Extension | AUMessageChannel (no App Groups) | Same — simpler provisioning |
| Library linking | Static via SPM in extension only | Static link RHVoice in extension |
| Data files | Copy to documents on first launch | Same for RHVoice data |
| SSML | Pass through to engine | RHVoice supports SSML too |
