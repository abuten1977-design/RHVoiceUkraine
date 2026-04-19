# Roadmap: Clean-Room RHVoice (Framework/XCFramework, macOS-first)

**Branch:** `clean-framework-macos-first`  
**Goal:** Move the RHVoice integration into a **dynamic framework / XCFramework** (LGPL-friendly), validate on **macOS first**, then reuse the same engine in iOS + VoiceOver extension.

This roadmap is written for accessibility-first development: each phase has a clear “done” checklist and produces a commit.

---

## Phase 0 — Preconditions (GitHub + build pipeline)

**Done when:**
- We can `git push` this branch to GitHub.
- We can trigger GitHub Actions workflows (manual `workflow_dispatch`).

**Output:**
- A branch pushed to `origin`.

---

## Phase 1 — Baseline inventory (no functional changes)

**Purpose:** Freeze what exists today so we can safely reuse code without reintroducing bugs.

**Done when:**
- Document which parts are “product code” vs “experiments”:
  - `UkrainianVoicesApp/` (XcodeGen app + extensions)
  - `RHVoiceUkrainianSynthesizer/` (SPM experiment)
  - `RHVoiceSpeechProject/` (framework prototype)
- Identify which engine/bridge code will be reused:
  - `UkrainianVoicesApp/Extension/Bridge/RHVoiceEngine.*`
  - `UkrainianVoicesApp/Extension/Provider/UkrainianSpeechSynthesizer.swift`
- Identify required resource layout:
  - `RHVoiceData/languages/Ukrainian/`
  - `RHVoiceData/voices/*`

**Output:**
- `docs/ARCHITECTURE.md` (module diagram + file map)
- `docs/LICENSE_NOTES.md` (clean-room + LGPL dynamic linking notes)

---

## Phase 2 — Create `RHVoiceKit` dynamic framework target

**Purpose:** Single place for the engine, streaming, buffers, diagnostics; reused by macOS + iOS targets.

**Rules:**
- Framework contains **no UI** and no `AVSpeechSynthesisProviderAudioUnit` subclass.
- Framework owns:
  - engine init
  - callbacks / streaming
  - ring buffer + ARC bridging rules
  - cancel + request token model

**Done when:**
- `RHVoiceKit.framework` builds for macOS locally/CI.
- Public API is stable and minimal (Swift-friendly where possible).

**Output:**
- New XcodeGen target or Xcode project target for `RHVoiceKit`.

---

## Phase 3 — Build `RHVoiceKit.xcframework` in GitHub Actions

**Purpose:** Produce a single deliverable that includes:
- iOS device (arm64)
- iOS simulator (arm64/x86_64)
- macOS (arm64/x86_64 as needed)

**Done when:**
- New CI workflow outputs `RHVoiceKit.xcframework` artifact.
- App builds link against the framework (not raw `.a` / loose `.dylib` paths).

**Output:**
- `.github/workflows/build-xcframework.yml`
- Artifact: `RHVoiceKit.xcframework`

---

## Phase 4 — macOS-first integration test app

**Purpose:** Fast iteration: validate engine init + voices + callbacks without iPhone/TestFlight friction.

**Done when (macOS app):**
- Preview button speaks all 4 voices.
- Logs show:
  - engine “ready” (voices/profiles detected)
  - `play_speech_callback` is invoked and audio frames are produced

**Output:**
- `UkrainianVoicesMac` links to `RHVoiceKit`.

---

## Phase 5 — iOS/VoiceOver extension integration

**Purpose:** Reuse proven `RHVoiceKit` in the extension.

**Done when (iPhone):**
- VoiceOver can select Ukrainian voice and speak reliably.
- No render-thread blocking (no `DispatchQueue.sync`, no `usleep`, no mutex waits).

**Output:**
- `UkrainianVoicesExtension` links to `RHVoiceKit`.

---

## Phase 6 — Quality upgrades (after it speaks)

Optional improvements inspired by the Polish app *ideas* (not code):
- SSML support (message type + parsing strategy)
- retry/silence-gate strategy for “first audio” stability
- engine lifecycle moved to correct AudioUnit lifecycle hooks

