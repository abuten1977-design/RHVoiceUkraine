# macOS Speech Synthesis Extension — Full Audit

Date: 2026-05-06

## Critical Issues (Parameters Not Applying)

### Issue 1: Per-voice pitch setting is discarded — hardcoded to 1.0

- **What**: `resolvedRequest()` hardcodes `pitch: 1.0` instead of using the per-voice `base.pitch` from settings.
- **Where**: `UkrainianSpeechSynthesizer.swift`, line ~172 (inside `resolvedRequest(for:)`)
- **Impact**: User changes pitch in the app settings for a specific voice, but the extension always sends pitch=1.0 to the engine. Pitch slider has no effect.
- **Fix**: Change `pitch: 1.0` to `pitch: base.pitch` in the `RHVoiceSpeechSettings` constructor.

### Issue 2: Per-voice volume setting is discarded — hardcoded to 1.0

- **What**: `resolvedRequest()` hardcodes `volume: 1.0` instead of using `base.volume` from settings.
- **Where**: `UkrainianSpeechSynthesizer.swift`, line ~170 (inside `resolvedRequest(for:)`)
- **Impact**: User changes volume in the app settings for a specific voice, but the extension always sends volume=1.0. Volume slider has no effect for per-voice overrides.
- **Fix**: Change `volume: 1.0` to `volume: base.volume`.

### Issue 3: Per-voice rate setting is discarded — hardcoded to 0.5

- **What**: `resolvedRequest()` hardcodes `rate: 0.5` instead of using `base.rate` from settings.
- **Where**: `UkrainianSpeechSynthesizer.swift`, line ~169 (inside `resolvedRequest(for:)`)
- **Impact**: User changes rate in the app settings for a specific voice, but the extension always uses 0.5 as the base rate. Only `speedMultiplier` is read from settings.
- **Fix**: Change `rate: 0.5` to `rate: base.rate`.

### Issue 4: Volume from settings is never passed to the engine

- **What**: `synthesizeSpeechRequest()` extracts `ssmlVolume` from SSML tags but never combines it with the per-voice volume setting (`request.settings.volume`). The settings volume is constructed but unused.
- **Where**: `UkrainianSpeechSynthesizer.swift`, lines ~93-100 (synthesizeSpeechRequest)
- **Impact**: Even if Issue 2 is fixed, the per-voice volume setting still won't reach the engine because only `ssmlVolume` is passed to `rhvoiceEngine.synthesize(...)`.
- **Fix**: Multiply `ssmlVolume` by `request.settings.volume` before passing to the engine, e.g.: `let effectiveVolume = ssmlVolume * request.settings.volume`.

### Issue 5: Pitch from settings is never combined with SSML pitch

- **What**: `synthesizeSpeechRequest()` passes `request.settings.pitch` to the engine but ignores any pitch information from SSML prosody tags. Conversely, the engine's `buildMessage` for SSML mode hardcodes `relative_pitch = 1.0`, ignoring the pitch parameter.
- **Where**: `RHVoiceEngine.mm`, line ~290 (`p.relative_pitch = 1.0` in SSML branch)
- **Impact**: When VoiceOver sends SSML (which is always), the pitch parameter from Swift is passed to `buildMessage` but then ignored — `relative_pitch` is always 1.0.
- **Fix**: In the SSML branch of `buildMessage`, set `p.relative_pitch = pitch` instead of `1.0`.

## High-Priority Issues

### Issue 6: App group container may be inaccessible on macOS without team ID

- **What**: macOS sandboxed apps require a properly provisioned app group. The entitlements use `group.rhvoice.UkrainianVoices.shared` but `DEVELOPMENT_TEAM` is empty in project.yml for local builds.
- **Where**: `project.yml` (UkrainianVoicesExtensionMac settings), `UkrainianVoicesExtensionMac.entitlements`
- **Impact**: `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` returns `nil` on macOS when the app group isn't properly provisioned. Settings snapshot file cannot be read. Extension falls back to `loadSnapshotFromLegacyDefaults()` which also uses `UserDefaults(suiteName:)` — this also returns nil without a valid group. Result: all settings are defaults, parameters never apply.
- **Fix**: Ensure the app group is registered in the Apple Developer portal and the provisioning profile includes it. For local dev, use `CODE_SIGN_IDENTITY: "-"` with a valid team ID, or add fallback logic that reads from standard UserDefaults when the group container is unavailable.

### Issue 7: `sentencePause` setting is read but never applied

- **What**: `resolvedRequest()` reads `base.sentencePause` and stores it in the request settings, but `synthesizeSpeechRequest()` never passes it to the engine. The `RHVoiceEngine.synthesize()` API doesn't accept a pause parameter.
- **Where**: `UkrainianSpeechSynthesizer.swift` (synthesizeSpeechRequest), `RHVoiceEngine.h`
- **Impact**: User adjusts sentence pause slider but it has no effect during VoiceOver playback.
- **Fix**: Use the `RHVoiceEngine+Parameters` category method `synthesize:voice:rate:volume:pitch:pauseDuration:` which processes pause via SSML break tags, or inject pause SSML before calling the base synthesize method.

### Issue 8: SSML rate extraction regex doesn't match VoiceOver's format

- **What**: `extractSSMLRate` looks for `rate="150%"` format, but macOS VoiceOver may send rate as a prosody attribute like `<prosody rate="fast">` or `rate="1.5"` (without %).
- **Where**: `UkrainianSpeechSynthesizer.swift`, `extractSSMLRate` method (~line 148)
- **Impact**: If VoiceOver sends rate in a format other than `NNN%`, the regex fails and defaults to 1.0. The system-requested speed change is ignored.
- **Fix**: Add fallback regex patterns for `rate="fast"`, `rate="slow"`, or bare decimal values without `%`.

### Issue 9: SSML volume extraction regex doesn't match VoiceOver's format

- **What**: `extractSSMLVolume` looks for `volume="NdB"` format, but VoiceOver may send volume as `volume="loud"`, `volume="50"` (0-100 scale), or `volume="+6dB"`.
- **Where**: `UkrainianSpeechSynthesizer.swift`, `extractSSMLVolume` method (~line 155)
- **Impact**: If VoiceOver sends volume in a format other than `±NdB`, the regex fails and defaults to 1.0. System volume adjustments are ignored.
- **Fix**: Add handling for named values (`silent`, `x-soft`, `soft`, `medium`, `loud`, `x-loud`) and bare numeric values (0-100 scale).

## Medium-Priority Issues

### Issue 10: `requestCounter` is not thread-safe

- **What**: `requestCounter` is incremented in `synthesizeSpeechRequest()` without synchronization. Multiple rapid VoiceOver requests could race.
- **Where**: `UkrainianSpeechSynthesizer.swift`, line ~86
- **Impact**: Minor — only affects log message IDs. No functional impact but indicates lack of thread safety awareness.
- **Fix**: Use `OSAtomicIncrement32` or move increment inside the lock, or use an actor.

### Issue 11: `internalRenderBlock` captures `self` strongly

- **What**: `performRender` is an instance method returned as the `internalRenderBlock`. This creates a strong reference cycle: AUAudioUnit → renderBlock → self.
- **Where**: `UkrainianSpeechSynthesizer.swift`, `internalRenderBlock` property (last line)
- **Impact**: The `UkrainianSpeechSynthesizer` instance is never deallocated. Memory leak grows with each extension reload.
- **Fix**: Return a closure that captures `[weak self]` or capture only the needed state (lock, outputData) in a separate struct.

### Issue 12: NSLock used in real-time audio render thread

- **What**: `performRender` acquires `NSLock` which can block the audio render thread. Priority inversion can cause audio glitches.
- **Where**: `UkrainianSpeechSynthesizer.swift`, `performRender` method
- **Impact**: Occasional audio dropouts or glitches, especially under system load. The render thread is real-time priority and must not block.
- **Fix**: Use `os_unfair_lock` (non-blocking for short critical sections) or a lock-free ring buffer pattern similar to what `RHVoiceEngine.mm` already uses.

### Issue 13: Fade-out applied to wrong buffer region when `toCopy < 128`

- **What**: The fade-out logic at end of render applies fade to the last 128 samples of the current render buffer. But if `toCopy` is less than 128, it fades the entire buffer including samples that were already output in previous render calls (they're in the same buffer pointer).
- **Where**: `UkrainianSpeechSynthesizer.swift`, performRender, fade-out section (~line 140)
- **Impact**: If the final render call has fewer than 128 frames, the fade is applied correctly (min clamps it). But the fade modifies the output buffer in-place after it was already filled — this is fine. Actually the logic `min(toCopy, 128)` is correct. Low impact.
- **Fix**: No fix needed — the `min(toCopy, 128)` handles this correctly.

### Issue 14: Completion signal delayed by one render cycle

- **What**: When all audio is consumed (`done = true`), the code sets `actionFlags = .offlineUnitRenderAction_Render` instead of `.offlineUnitRenderAction_Complete`. Completion is only signaled on the *next* empty render call.
- **Where**: `UkrainianSpeechSynthesizer.swift`, performRender (~line 145)
- **Impact**: Adds one extra render cycle (typically 10-20ms) of silence before the host knows speech is done. Minor latency at end of utterance.
- **Fix**: This is intentional (comment says "so hosts do not discard the final buffer"). Acceptable trade-off.

## Low-Priority Issues

### Issue 15: `outputData` array copied on every synthesis request

- **What**: `Array(UnsafeBufferPointer(...))` copies the entire PCM buffer into a Swift Array. For long utterances this could be megabytes.
- **Where**: `UkrainianSpeechSynthesizer.swift`, line ~113
- **Impact**: Memory spike during synthesis. For typical VoiceOver utterances (short), this is acceptable. For reading long documents, could cause memory pressure.
- **Fix**: Use `Data` or keep the `AVAudioPCMBuffer` alive and read directly from its pointer.

### Issue 16: `MessageChannel` inner class doesn't properly implement protocol

- **What**: `callHostBlock` property getter always returns nil and setter is no-op. This is required by `AUMessageChannel` protocol.
- **Where**: `UkrainianSpeechSynthesizer.swift`, `messageChannel(for:)` method
- **Impact**: Host app cannot call back into the extension. Currently unused but could cause issues if macOS tries to use this channel.
- **Fix**: Store and return the `callHostBlock` properly if bidirectional communication is needed.

### Issue 17: macOS extension embeds RHVoiceKitMac framework (potential duplicate symbols)

- **What**: `UkrainianVoicesExtensionMac` has `embed: true` for `RHVoiceKitMac` dependency, and the parent app `UkrainianVoicesMac` also embeds it.
- **Where**: `project.yml`, UkrainianVoicesExtensionMac dependencies
- **Impact**: The framework is embedded twice in the final .app bundle (once in app's Frameworks/, once in extension's Frameworks/). Increases bundle size. On iOS the extension uses `embed: false` — the macOS version diverges.
- **Fix**: Change to `embed: false` for the extension and ensure `LD_RUNPATH_SEARCH_PATHS` includes `@executable_path/../../../../Frameworks` (already present). The extension will find the framework in the parent app's Frameworks directory.

## Summary of Root Cause for "Parameters Don't Apply to All Voices"

The primary root cause is in `resolvedRequest(for:)` which **hardcodes** rate=0.5, volume=1.0, pitch=1.0 regardless of what the user configured per-voice. It only reads `speedMultiplier` and `sentencePause` from the settings snapshot. Combined with the engine's SSML branch ignoring the pitch parameter, the result is:

1. **Rate**: Only `speedMultiplier` from settings is applied (multiplied with SSML rate). The base `rate` setting is ignored.
2. **Volume**: Always 1.0 from settings side. Only SSML-extracted volume applies.
3. **Pitch**: Always 1.0. Neither settings nor SSML pitch reaches the engine.

This affects **all voices equally** — but users may perceive it as "not applying to all voices" because:
- If they set custom per-voice settings (useCustomSettings=true), those are loaded but then the values are overwritten with hardcoded constants.
- The general settings also don't apply because the same hardcoding happens regardless of which path `effectiveSettings(for:)` returns.

### Minimal Fix (Issues 1-5)

In `UkrainianSpeechSynthesizer.swift`, `resolvedRequest(for:)`:
```swift
settings: RHVoiceSpeechSettings(
    rate:            base.rate,
    volume:          base.volume,
    speedMultiplier: base.speedMultiplier,
    sentencePause:   base.sentencePause,
    pitch:           base.pitch
)
```

In `synthesizeSpeechRequest()`, combine settings volume with SSML volume:
```swift
let effectiveVolume = ssmlVolume * request.settings.volume
```

In `RHVoiceEngine.mm`, `buildMessage` SSML branch:
```objc
p.relative_pitch = pitch;
```
