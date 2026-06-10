# eSpeak vs RHVoice iOS Extension — Detailed Comparison

Generated: 2026-05-09

---

## 1. Voice Registration (`speechVoices` property)

### eSpeak approach:
- Returns ALL voices unconditionally — iterates `systemLanguages` × `exposedLocales` × voice variants
- No filtering by user "enabled" settings — every voice is always visible to the system
- Voices are generated dynamically from the engine's voice list at runtime

### RHVoice approach:
- Reads `enabledVoiceIdentifiers` from shared settings snapshot
- Filters `staticVoices` to only return voices the user enabled in the app
- Falls back to all voices only if the filtered list is empty

### Change needed:

- **WHAT**: Always return all voices from `speechVoices` getter, remove settings-based filtering
- **WHY**: iOS caches the voice list. If a voice isn't returned when the system queries, it won't appear in Settings > Accessibility > Spoken Content. eSpeak always exposes everything so the system always knows about all voices. Filtering causes voices to "disappear" until the extension is reloaded.
- **RISK**: Users who disabled voices in the app will still see them in iOS Settings. Minor UX confusion but no functional breakage.
- **PRIORITY**: HIGH

---

## 2. `synthesizeSpeechRequest` — Synchronous vs Streaming

### eSpeak approach:
- **Fully synchronous**: calls `espeak_ng_Synthesize()` + `espeak_ng_Synchronize()` which blocks until ALL audio is generated
- Converts Int16 samples to Float32 using vDSP in one shot
- Stores the complete `output` array, sets `outputOffset = 0`
- All protected by a single `DispatchSemaphore(value: 1)` (mutex pattern)
- No background queue — synthesis runs directly on the calling thread

### RHVoice iOS approach:
- **Streaming/async**: dispatches synthesis to `synthesisQueue`
- Uses `RHVoiceAudioBuffer` (ring buffer) for lock-free SPSC producer/consumer
- `audioBuffer.beginRequest()` creates a token; samples are appended incrementally via callback
- `audioBuffer.markCompleted(with:)` signals end of stream

### Change needed:

- **WHAT**: Replace streaming ring buffer model with synchronous "synthesize all, then serve" model on iOS (matching our macOS path)
- **WHY**: eSpeak's approach is simpler and proven to work with iOS's audio unit render pipeline. The streaming model introduces timing complexity — if render calls arrive before enough samples are buffered, you get silence gaps or underruns. The synchronous model guarantees all audio is ready before the first render call.
- **RISK**: Longer initial latency for long utterances (user waits for full synthesis before hearing anything). For short VoiceOver utterances this is negligible. For very long text, could cause noticeable delay.
- **PRIORITY**: HIGH

---

## 3. `performRender` — Buffer Serving

### eSpeak approach:
- `outputMutex.wait()` (semaphore lock)
- Copies `min(output.count - outputOffset, frameCount)` samples to output buffer
- Sets `mDataByteSize` to actual bytes copied (NOT full frameCount × 4)
- When `outputOffset >= output.count`: sets `.offlineUnitRenderAction_Complete` AND clears the array
- `outputMutex.signal()` (unlock)
- **No pre-buffering logic** — serves whatever is available immediately
- **No fade-out** — just stops

### RHVoice iOS approach:
- Uses `audioBuffer.renderFrames()` with a `preBufferFrames: 2400` parameter
- Sets `mDataByteSize` to full `requestedFrames * 4` always (even for silence)
- Completion signaled by `didComplete` out-parameter from ring buffer

### RHVoice macOS approach (closer to eSpeak):
- Uses `NSLock` instead of semaphore
- Has a `synthesisComplete` flag to distinguish "still synthesizing" from "done"
- Applies fade-out on last chunk
- Sets `mDataByteSize` to full frame size always

### Changes needed:

- **WHAT**: Set `mDataByteSize` to actual copied bytes count (not full buffer size) when signaling completion
- **WHY**: eSpeak sets `mDataByteSize = count * 4` where count is actual samples copied. This tells the audio pipeline exactly how much valid data exists. Setting it to the full requested size when some frames are zero-filled may cause the system to play trailing silence or misinterpret buffer boundaries.
- **RISK**: Low — this is a correctness fix. Could theoretically cause issues if the system expects full buffers, but eSpeak proves it works.
- **PRIORITY**: MEDIUM

- **WHAT**: Remove `preBufferFrames` logic — serve samples immediately without waiting for a threshold
- **WHY**: With synchronous synthesis, all samples are ready before render starts. Pre-buffering is unnecessary and adds complexity.
- **RISK**: None if synthesis is synchronous. If keeping streaming, removing pre-buffer could cause audio glitches.
- **PRIORITY**: MEDIUM (becomes automatic if switching to synchronous model)

- **WHAT**: Clear the output array after signaling complete (like eSpeak does `self.output.removeAll()`)
- **WHY**: Frees memory immediately. eSpeak clears inside the mutex-protected render block. Our macOS path doesn't clear, potentially holding large buffers in memory.
- **RISK**: None — data is no longer needed after completion.
- **PRIORITY**: LOW

---

## 4. Cancel Implementation

### eSpeak approach:
- `outputMutex.wait()`
- `output.removeAll()`
- `outputOffset = 0`
- `outputMutex.signal()`
- Does NOT call any espeak cancel/stop function

### RHVoice iOS approach:
- Calls `rhvoiceEngine.cancel()` (stops the engine)
- Calls `audioBuffer.cancelCurrentRequest()` (ring buffer cancel)
- Sets `currentToken = nil`

### RHVoice macOS approach:
- Calls `rhvoiceEngine.cancel()`
- Clears `outputData`, resets offset, sets `synthesisComplete = true`

### Change needed:

- **WHAT**: Simplify cancel to just clear the output buffer under lock (like eSpeak). Keep `rhvoiceEngine.cancel()` since RHVoice may be mid-synthesis on a background thread.
- **WHY**: eSpeak doesn't need to cancel the engine because synthesis is synchronous and already complete by the time cancel could be called. For RHVoice, if we switch to synchronous model, the engine call may still be needed if cancel arrives during synthesis.
- **RISK**: If synthesis is truly synchronous (blocks `synthesizeSpeechRequest`), then cancel can only arrive after synthesis completes, making `rhvoiceEngine.cancel()` a no-op. If we keep any async path, we still need it.
- **PRIORITY**: MEDIUM

---

## 5. Completion Signaling

### eSpeak approach:
- Sets `.offlineUnitRenderAction_Complete` when `outputOffset >= output.count`
- This happens INSIDE the semaphore-protected section
- Immediately clears the buffer in the same protected section
- No separate "synthesisComplete" flag — completion is determined purely by buffer exhaustion

### RHVoice iOS approach:
- Ring buffer's `renderFrames` sets `didComplete` out-parameter
- Completion depends on both: all samples consumed AND `markCompleted` was called

### RHVoice macOS approach:
- Has a separate `synthesisComplete` boolean flag
- When buffer is empty AND `synthesisComplete == false`: sends silence (`.offlineUnitRenderAction_Render`)
- When buffer is empty AND `synthesisComplete == true`: sends `.offlineUnitRenderAction_Complete`

### Change needed:

- **WHAT**: Remove the `synthesisComplete` flag; determine completion purely by "output buffer is exhausted" (since with synchronous model, buffer is always complete before render starts)
- **WHY**: eSpeak's simpler model works because synthesis is done before render begins. No need to distinguish "still synthesizing" from "done" states.
- **RISK**: If synthesis ever fails silently (produces 0 samples), we'd immediately signal complete with no audio. Should handle this edge case.
- **PRIORITY**: MEDIUM

---

## 6. Thread Safety Mechanism

### eSpeak approach:
- `DispatchSemaphore(value: 1)` — used as a mutex
- Protects: `output` array and `outputOffset`
- Used in: `performRender`, `synthesizeSpeechRequest`, `cancelSpeechRequest`
- Simple wait/signal pattern

### RHVoice iOS approach:
- `RHVoiceAudioBuffer` — lock-free SPSC ring buffer
- Producer: synthesis queue appends samples
- Consumer: render thread reads samples
- Token-based request tracking

### RHVoice macOS approach:
- `NSLock` — standard mutex
- Protects: `outputData`, `outputOffset`, `synthesisComplete`

### Change needed:

- **WHAT**: Replace ring buffer with `DispatchSemaphore(value: 1)` mutex pattern (or keep NSLock — functionally equivalent)
- **WHY**: With synchronous synthesis, a simple mutex is sufficient. The ring buffer adds complexity for a streaming model we wouldn't be using. DispatchSemaphore is slightly more efficient than NSLock for this use case (no objc_msgSend overhead).
- **RISK**: NSLock and DispatchSemaphore are both fine. The real risk is in removing the ring buffer if we ever want streaming back. Consider keeping ring buffer code but not using it.
- **PRIORITY**: MEDIUM

---

## 7. Info.plist Differences

### eSpeak:
- `description`: "Synth"
- `manufacturer`: "ESPK"
- `name`: "eSpeak-NG" (short, no prefix pattern)
- `subtype`: "espk"
- No `CFBundleDevelopmentRegion`, `CFBundleDisplayName`, `CFBundleVersion` etc.
- Minimal plist — only NSExtension section

### RHVoice:
- `description`: "RHVoice Ukrainian Speech Synthesizer"
- `manufacturer`: "RHVo"
- `name`: "RHVo: RHVoice Ukrainian Speech Synthesizer" (uses "manufacturer: description" pattern)
- `subtype`: "rhvc"
- Full plist with `CFBundleDevelopmentRegion`, `CFBundleDisplayName`, `CFBundlePackageType`, etc.

### Change needed:

- **WHAT**: No functional changes needed — the plist differences are cosmetic/identity
- **WHY**: The AudioComponent registration fields (type=ausp, tags=Speech Synthesizer, sandboxSafe=true) are identical. The manufacturer/subtype/name are just identifiers.
- **RISK**: N/A
- **PRIORITY**: LOW (no change needed)

---

## 8. Other Differences

### 8a. Sample Rate

- **WHAT**: eSpeak uses 22050 Hz, RHVoice uses 24000 Hz
- **WHY**: Each engine's native output rate. RHVoice generates at 24kHz natively.
- **RISK**: No change needed — this is engine-specific.
- **PRIORITY**: LOW (no change needed)

### 8b. Parameter Tree (AUParameterTree)

- **WHAT**: eSpeak exposes rate/volume/pitch/wordGap/range/ssml_breaks as AU parameters; RHVoice does not
- **WHY**: eSpeak allows the host app to adjust parameters via the standard AU parameter mechanism. RHVoice uses shared UserDefaults/file-based settings instead.
- **RISK**: Adding AU parameters could allow more dynamic control but is not required for basic functionality.
- **PRIORITY**: LOW

### 8c. Engine Initialization

- **WHAT**: eSpeak uses a singleton `EspeakContainer.single` initialized on main thread; RHVoice uses a lazy `rhvoiceEngine` property
- **WHY**: eSpeak ensures single initialization via main-thread dispatch. RHVoice's lazy init is simpler but could theoretically race.
- **RISK**: If `allocateRenderResources` and `synthesizeSpeechRequest` race, lazy init could be called twice. Low probability in practice.
- **PRIORITY**: LOW

### 8d. SSML Handling

- **WHAT**: eSpeak passes SSML directly to the engine (`espeakSSML` flag); RHVoice extracts rate/volume from SSML via regex, then passes text to engine
- **WHY**: eSpeak's engine natively handles SSML. RHVoice's engine may not fully support SSML prosody tags, so we extract and apply them manually.
- **RISK**: No change needed — this is engine-specific behavior.
- **PRIORITY**: LOW (no change needed)

### 8e. No Fade-Out in eSpeak

- **WHAT**: eSpeak has no fade-out logic on the last audio chunk; RHVoice macOS applies a 32-sample fade
- **WHY**: eSpeak's audio apparently doesn't produce clicks at the end. RHVoice may produce a DC offset or abrupt cutoff.
- **RISK**: Removing fade-out could cause audible clicks. Keep it unless testing shows it's unnecessary.
- **PRIORITY**: LOW

---

## Summary: Priority Changes

| # | Change | Priority |
|---|--------|----------|
| 1 | Always return all voices (remove settings filter) | HIGH |
| 2 | Switch iOS to synchronous synthesis (block until done) | HIGH |
| 3 | Set mDataByteSize to actual copied bytes | MEDIUM |
| 4 | Remove preBufferFrames logic | MEDIUM |
| 5 | Simplify cancel (clear buffer under lock) | MEDIUM |
| 6 | Remove synthesisComplete flag, use buffer exhaustion | MEDIUM |
| 7 | Replace ring buffer with simple mutex + array | MEDIUM |
| 8 | Clear output array after completion | LOW |

---

## Recommended Implementation Order

1. **Return all voices always** (1 line change, immediate impact)
2. **Switch to synchronous model** (biggest architectural change — unify iOS with macOS path)
3. **Adopt semaphore/lock + flat array** (follows naturally from #2)
4. **Fix mDataByteSize** (small correctness fix)
5. **Simplify cancel** (follows from #2-3)
6. **Remove synthesisComplete flag** (follows from #2)
7. **Clear buffer on complete** (trivial)
