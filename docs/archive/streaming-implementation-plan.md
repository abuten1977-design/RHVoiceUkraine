# Streaming Synthesis Implementation Plan

**Target file:** `UkrainianVoicesApp/Extension/Provider/UkrainianSpeechSynthesizer.swift`  
**Scope:** iOS only (`#if os(iOS)`) — macOS keeps current synchronous approach.

---

## Summary

Replace the synchronous `synthesize()` → flat `[Float]` array model with:
1. `synthesizeSpeechRequest()` calls `RHVoiceAudioBuffer.beginRequest()` then starts `synthesizeStreaming:onChunk:` on a background thread
2. The `onChunk` callback feeds samples into `RHVoiceAudioBuffer` via `appendSamples:count:token:`
3. `performRender()` reads from `RHVoiceAudioBuffer.renderFrames:maxFrames:preBufferFrames:didComplete:`
4. Cancel calls `RHVoiceAudioBuffer.cancelCurrentRequest()` + `rhvoiceEngine.cancel()`
5. No `NSLock` needed on iOS — `RHVoiceAudioBuffer` is internally lock-free (SPSC ring buffer)

---

## Properties to Change

### Remove (iOS only)

```swift
// These are only needed for the synchronous flat-array model:
private var outputData: [Float] = []
private var outputOffset: Int = 0
private var synthesisComplete: Bool = true
private let lock = NSLock()
```

### Add (iOS only)

```swift
#if os(iOS)
private lazy var audioBuffer: RHVoiceAudioBuffer = RHVoiceAudioBuffer()
private var currentToken: RHVoiceAudioRequestToken?
private let synthesisQueue = DispatchQueue(label: "com.rhvoice.synthesis.streaming", qos: .userInitiated)
#endif
```

### Keep (both platforms)

```swift
private lazy var rhvoiceEngine: RHVoiceEngine = RHVoiceEngine()
private let outputBus: AUAudioUnitBus
private static let staticVoices: [AVSpeechSynthesisProviderVoice] = [...]
private var outputBussesStorage: AUAudioUnitBusArray!
private var requestCounter: Int = 0
```

---

## Full Property Section (refactored)

```swift
public final class UkrainianSpeechSynthesizer: AVSpeechSynthesisProviderAudioUnit {
    private lazy var rhvoiceEngine: RHVoiceEngine = RHVoiceEngine()
    private let outputBus: AUAudioUnitBus

    #if os(iOS)
    // Streaming model: lock-free SPSC ring buffer
    private lazy var audioBuffer: RHVoiceAudioBuffer = RHVoiceAudioBuffer()
    private var currentToken: RHVoiceAudioRequestToken?
    private let synthesisQueue = DispatchQueue(label: "com.rhvoice.synthesis.streaming", qos: .userInitiated)
    #else
    // Synchronous model: flat array + read offset
    private var outputData: [Float] = []
    private var outputOffset: Int = 0
    private var synthesisComplete: Bool = true
    private let lock = NSLock()
    #endif

    // ... rest unchanged
}
```

---

## Method Changes

### 1. `synthesizeSpeechRequest(_:)` — iOS streaming version

```swift
#if os(iOS)
public override func synthesizeSpeechRequest(_ speechRequest: AVSpeechSynthesisProviderRequest) {
    requestCounter += 1
    let reqId = requestCounter
    let request = resolvedRequest(for: speechRequest)

    rhLog("req#\(reqId) START voice=\(request.voiceProfileName) text=\(request.text.count) chars")

    let ssmlRate = Self.extractSSMLRate(from: request.text)
    let ssmlVolume = Self.extractSSMLVolume(from: request.text)
    let mappedRate = ssmlRate <= 2.0 ? ssmlRate : 2.0 + log(ssmlRate / 2.0) * 1.5
    let effectiveRate = mappedRate * request.settings.speedMultiplier
    let cappedRate = min(effectiveRate, 4.0)
    let effectiveVolume = ssmlVolume * request.settings.volume

    rhLog("req#\(reqId) ssmlRate=\(String(format: "%.2f", ssmlRate)) → mapped=\(String(format: "%.2f", mappedRate)) × mult=\(String(format: "%.2f", request.settings.speedMultiplier)) → rate=\(String(format: "%.2f", cappedRate)) vol=\(String(format: "%.2f", effectiveVolume))")

    // Begin new request — invalidates any previous token
    let token = audioBuffer.beginRequest()
    currentToken = token

    let text = request.text
    let voice = request.voiceProfileName
    let pitch = request.settings.pitch

    synthesisQueue.async { [weak self] in
        guard let self = self else { return }

        self.rhvoiceEngine.synthesizeStreaming(
            text,
            voice: voice,
            rate: cappedRate,
            volume: effectiveVolume,
            pitch: pitch
        ) { samples, count, sampleRate in
            // onChunk callback — push into ring buffer
            guard let samples = samples, count > 0 else { return }
            self.audioBuffer.appendSamples(samples, count: count, token: token)
        }

        // Synthesis complete — mark buffer done
        self.audioBuffer.markCompleted(with: token)
        rhLog("req#\(reqId) streaming synthesis COMPLETE")
    }
}
#else
// macOS: keep existing synchronous implementation unchanged
public override func synthesizeSpeechRequest(_ speechRequest: AVSpeechSynthesisProviderRequest) {
    // ... existing code verbatim ...
}
#endif
```

### 2. `cancelSpeechRequest()` — iOS streaming version

```swift
#if os(iOS)
public override func cancelSpeechRequest() {
    rhLog("cancelSpeechRequest (streaming)")
    rhvoiceEngine.cancel()
    audioBuffer.cancelCurrentRequest()
    currentToken = nil
}
#else
public override func cancelSpeechRequest() {
    rhLog("cancelSpeechRequest")
    rhvoiceEngine.cancel()
    lock.lock()
    outputData = []
    outputOffset = 0
    synthesisComplete = true
    lock.unlock()
}
#endif
```

### 3. `performRender(...)` — iOS streaming version

```swift
#if os(iOS)
private func performRender(
    actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    timestamp: UnsafePointer<AudioTimeStamp>,
    frameCount: AUAudioFrameCount,
    outputBusNumber: Int,
    outputAudioBufferList: UnsafeMutablePointer<AudioBufferList>,
    renderEvents: UnsafePointer<AURenderEvent>?,
    renderPull: AURenderPullInputBlock?
) -> AUAudioUnitStatus {
    let audioBuffers = UnsafeMutableAudioBufferListPointer(outputAudioBufferList)
    guard let data = audioBuffers[0].mData else {
        return kAudioUnitErr_InvalidParameter
    }

    let frames = data.assumingMemoryBound(to: Float.self)
    let requestedFrames = Int(frameCount)

    // Zero-fill first
    frames.update(repeating: 0, count: requestedFrames)
    audioBuffers[0].mDataByteSize = UInt32(requestedFrames * MemoryLayout<Float>.size)
    audioBuffers[0].mNumberChannels = 1

    // Pre-buffer: wait for 2400 frames (100ms) before starting playback
    var didComplete: ObjCBool = false
    let rendered = audioBuffer.renderFrames(
        frames,
        maxFrames: UInt(requestedFrames),
        preBufferFrames: 2400,
        didComplete: &didComplete
    )

    if rendered {
        actionFlags.pointee = didComplete.boolValue
            ? .offlineUnitRenderAction_Complete
            : .offlineUnitRenderAction_Render
    } else {
        actionFlags.pointee = didComplete.boolValue
            ? .offlineUnitRenderAction_Complete
            : .offlineUnitRenderAction_Render
    }

    return noErr
}
#else
private func performRender(
    // ... existing macOS implementation unchanged ...
) -> AUAudioUnitStatus {
    // ... existing code verbatim ...
}
#endif
```

---

## How Cancel Works

1. **Swift layer:** `cancelSpeechRequest()` calls:
   - `rhvoiceEngine.cancel()` — sets `cancelled` flag on the active `EngineState`, wakes the consumer thread via `NSCondition.broadcast()`. The `play_speech_callback` returns 0 on next invocation, stopping `RHVoice_speak`.
   - `audioBuffer.cancelCurrentRequest()` — marks the `AudioRequestState` as completed + cancelling, sets `cancelFadeFramesRemaining = 240` (10ms fade-out at 24kHz).

2. **Render side:** Next `renderFrames` call sees `cancelling=true`, applies linear fade-out over remaining frames, then reports `didComplete=true`.

3. **Producer thread:** `synthesizeStreaming` consumer loop sees `cancelled=true`, breaks out. The `shared_ptr<EngineState>` ensures no use-after-free.

---

## How Completion is Signaled

1. `RHVoice_speak` finishes → `synthesizeStreaming:onChunk:` consumer loop drains remaining chunks, then returns.
2. After `synthesizeStreaming` returns, we call `audioBuffer.markCompleted(with: token)` which sets `state->completed = true`.
3. In `performRender`, `renderFrames:maxFrames:preBufferFrames:didComplete:` returns `didComplete=true` when:
   - `queuedSamples == 0` AND `completed == true` AND current chunk exhausted.
4. Swift sets `actionFlags = .offlineUnitRenderAction_Complete` → system stops calling render.

---

## Thread Safety Analysis

| Thread | Role | Access |
|--------|------|--------|
| Main/AU thread | Calls `synthesizeSpeechRequest`, `cancelSpeechRequest` | Writes `currentToken`, calls `beginRequest`/`cancelCurrentRequest` |
| `synthesisQueue` (background) | Runs `synthesizeStreaming` | Calls `appendSamples:count:token:` and `markCompleted:` |
| Render thread (real-time) | Calls `performRender` | Calls `renderFrames:maxFrames:preBufferFrames:didComplete:` |

**Safety guarantees:**
- `RHVoiceAudioBuffer` uses `std::atomic` operations and a lock-free SPSC ring buffer — safe for single-producer (synthesis queue) / single-consumer (render thread).
- `beginRequest()` creates a new `AudioRequestState` via `std::shared_ptr` with atomic store — old state is safely abandoned.
- `cancelCurrentRequest()` only sets atomic flags on the current state — no data race with render.
- `currentToken` is only accessed from the main/AU thread (synthesize and cancel are serialized by the AU framework).
- The `synthesisQueue` serial queue ensures only one streaming operation runs at a time.

---

## What Stays the Same for macOS

Everything inside `#else` blocks:
- `outputData: [Float]`, `outputOffset`, `synthesisComplete`, `lock` properties
- Synchronous `synthesizeSpeechRequest` calling `rhvoiceEngine.synthesize()`
- Lock-based `performRender` reading from flat array
- Lock-based `cancelSpeechRequest`

All shared code (unchanged on both platforms):
- `init(componentDescription:options:)`
- `outputBusses`
- `allocateRenderResources()`
- `speechVoices`
- `messageChannel(for:)`
- `internalRenderBlock` (returns `performRender` — the function itself is platform-specific)
- `extractSSMLRate(from:)`, `extractSSMLVolume(from:)`
- `resolvedRequest(for:)`
- `staticVoices`

---

## Pre-buffer Tuning

The `preBufferFrames: 2400` parameter (100ms at 24kHz) provides hysteresis:
- Render won't start outputting audio until 2400 samples are buffered
- Once started, it plays continuously even if buffer dips below threshold
- This prevents choppy output from slow synthesis while keeping latency low

Can be tuned: lower = less latency but risk of underruns; higher = smoother but delayed start.

---

## Migration Checklist

- [ ] Add `#if os(iOS)` / `#else` / `#endif` around property declarations
- [ ] Add `#if os(iOS)` / `#else` / `#endif` around `synthesizeSpeechRequest`
- [ ] Add `#if os(iOS)` / `#else` / `#endif` around `cancelSpeechRequest`
- [ ] Add `#if os(iOS)` / `#else` / `#endif` around `performRender`
- [ ] Verify `RHVoiceAudioBuffer` is exposed to Swift via bridging header (already in `Extension/Bridge/RHVoiceEngine.h`)
- [ ] Test: VoiceOver reads a sentence → audio plays without gaps
- [ ] Test: Cancel mid-sentence → audio fades out cleanly (no click)
- [ ] Test: Rapid cancel+new request → no crash, new audio plays
- [ ] Test: macOS build still compiles and works with synchronous path
