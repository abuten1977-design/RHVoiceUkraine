# RHVoice Ukrainian — Architecture Documentation (New Docs)

This folder documents the **current architecture** of the RHVoice Ukrainian project
(Ukrainian voices for Apple VoiceOver on iOS and macOS via a Speech Synthesis
Provider Extension), the data/parameter pipeline, the build/CI setup, and the
engineering difficulties we hit and how we solved them.

**Purpose:** these docs are written so an automated analysis agent (e.g. Gemini)
and human reviewers can understand the system and look for potential problems
without having to reverse‑engineer the whole codebase first.

Docs are written in English for analysis tooling; identifiers, file paths and
commit hashes are exact and copy‑paste‑safe.

## Repository

- GitHub repo: `abuten1977-design/RHVoiceUkraine`
- Active working branch: `ci/macos-gates-2026-04-26`
- Documented commit (HEAD at time of writing): `f9c1c6c0` ("Fix SSML pauses and add word gap")
- Local clean clone used while writing: `/home/butenhome/aiwork/copilot/RHVoiceUkraine_task008`

## How to read these docs

Read in this order:

1. **ARCHITECTURE.md** — the system: platforms, Xcode targets, the RHVoice C
   engine integration model, the Speech Synthesis Provider Extension, the App
   Group settings sync, the synthesis pipeline, modules/classes/functions and
   how they connect.
2. **PARAMS_AND_BUILD.md** — the speech parameter pipeline in detail (rate /
   accelerator / volume / pitch / sentence pause / word gap), the speed curve
   and engine ceiling, bilingual/Latin handling, and the build + CI workflows
   (how an iOS TestFlight build and a signed macOS build are produced).
3. **CHALLENGES_AND_SOLUTIONS.md** — the hard problems encountered (architectural
   pivot, the engine speed wall, iOS vs macOS VoiceOver rate scale, App Group
   uncertainty, code‑signing, SSML corruption, accessibility duplication) and
   exactly how each was diagnosed and resolved. **This is the most useful file
   for finding latent/potential problems** — it records what is fragile and why.

## Where the code lives (entry points)

- Speech provider extension entry: `UkrainianVoicesApp/Extension/Provider/UkrainianSpeechSynthesizer.swift`
- Shared settings model + App Group store: `UkrainianVoicesApp/Shared/RHVoiceSharedSettings.swift`
- App UI: `UkrainianVoicesApp/App/ContentView.swift`
- Engine Obj‑C++ bridge (iOS via SwiftPM): `RHVoiceCore/Bridge/Sources/RHVoiceEngine.mm`
- Engine Obj‑C++ bridge (macOS in‑target): `RHVoiceKit/Sources/RHVoiceEngine.mm`
- RHVoice C/C++ engine: `RHVoice/src/core/` (notably `params.cpp`, `language.cpp`,
  `ukrainian.cpp`, `hts_label.cpp`), Sonic time‑stretch in `RHVoice/external/libs/sonic/`
- Bundled voice/language data: `UkrainianVoicesApp/Extension/Resources/RHVoiceData/`
- Engine config: `UkrainianVoicesApp/Extension/Resources/RHVoiceData/RHVoice.conf`
- Xcode project generator input: `UkrainianVoicesApp/project.yml` (XcodeGen)
- iOS SwiftPM engine package: `RHVoiceCore/Package.swift`
- CI: `.github/workflows/` (`build.yml` = iOS→TestFlight, `build-mac-signed.yml` = signed macOS)

## Status snapshot (documented commit)

- iOS speed is controlled **only** by the VoiceOver rotor (app has no speed control).
- App per‑voice controls: **Accelerator** (×1–×4 multiplier), **Sentence pause**,
  **Word gap**. Volume/pitch are intentionally neutral (VoiceOver owns them).
- English/Latin words use the bundled English module + `bilingual=English`
  (no transliteration fallback).
- Known open verification items are listed in CHALLENGES_AND_SOLUTIONS.md §"Open risks".
