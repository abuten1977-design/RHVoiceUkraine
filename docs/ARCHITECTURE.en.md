# RHVoice Ukrainian Architecture

This document describes the architecture as implemented in the code.

> 🇺🇦 Українською: [ARCHITECTURE.uk.md](ARCHITECTURE.uk.md)

## Overview

RHVoice Ukrainian is a **system voice provider** for VoiceOver, not a standalone reader. Apple
lets third-party synthesizers integrate with VoiceOver through the
`AVSpeechSynthesisProviderAudioUnit` class (iOS 16+, macOS 13+). Our extension implements this
class, and the system calls into it whenever it needs to speak text with a chosen Ukrainian voice.

The product has two parts:

- **Host app** (`UkrainianVoices` / `UkrainianVoicesMac`) — SwiftUI UI: enabling voices, tuning
  controls, personal dictionary, sample preview.
- **Synthesizer extension** (`UkrainianVoicesExtension` / `…Mac`) — a separate system process that
  receives VoiceOver requests and returns audio.

The two parts exchange settings through an **App Group**
(`group.rhvoice.UkrainianVoices.shared`).

## Build (XcodeGen)

The single source of build truth is `UkrainianVoicesApp/project.yml` (an XcodeGen manifest). The
`.xcodeproj` itself is not committed; it is generated with `xcodegen generate`.

Main targets:

| Target | Type | Platform | Role |
|--------|------|----------|------|
| `UkrainianVoices` | app | iOS | Host app, settings UI |
| `UkrainianVoicesExtension` | extension | iOS | Synthesizer (AVSpeechSynthesisProviderAudioUnit) |
| `UkrainianVoicesMac` | app | macOS | macOS host app |
| `UkrainianVoicesExtensionMac` | extension | macOS | macOS synthesizer |
| `RHVoiceKit` / `RHVoiceKitMac` | framework | iOS / macOS | Engine wrapper; on macOS compiles the C/C++ engine in-target |

The RHVoice engine is **compiled statically** into the bundle (Apple requirement: no dynamic
`.dylib`s).

## Synthesis pipeline (text → audio)

The path from a VoiceOver request to audio:

1. **Request intake.** `UkrainianSpeechSynthesizer`
   (`UkrainianVoicesApp/Extension/Provider/UkrainianSpeechSynthesizer.swift`) receives SSML text
   from VoiceOver together with the voice and parameters (rate, volume, pitch).

2. **Parameter parsing.** `rate`, `volume`, `pitch` are parsed from the SSML. Rate is mapped to an
   engine multiplier through a **platform-specific curve** (iOS and macOS have different speed
   ceilings), then multiplied by the user's "accelerator" setting.

3. **Text preparation:**
   - `RHVoicePipelineSplitter` (`UkrainianVoicesApp/Shared/RHVoicePipelineSplitter.swift`) splits
     the text **by sentences** and strips SSML tags the engine doesn't understand (e.g. `<say-as>`,
     `<voice>`) while keeping the text. This makes long text start speaking immediately.
   - **Apostrophe normalization** maps the different apostrophe variants to the form the engine
     pronounces correctly.
   - **Number/decimal normalization** expands numbers into Ukrainian words where needed.
   - Sentence pauses and word gaps are inserted as configured.

4. **Synthesis.** `RHVoiceEngine` (an Objective-C++ bridge, `RHVoiceEngine.mm`) calls the RHVoice
   engine **synchronously** (`RHVoice_speak`) for each fragment. The engine returns PCM chunks via
   a callback; they are collected into a buffer and converted to Float32.

5. **Audio delivery.** `performRender` works in a **pull** fashion (eSpeak-style): the system
   periodically asks for the next audio frames, and the extension hands back already-synthesized
   data from a flat buffer. Sample rate is **24 kHz**, mono.

> **Note:** the implementation is **synchronous, not streaming**. The engine fully synthesizes a
> fragment first, and only then the audio is delivered. Sentence splitting reduces the perceived
> start-up latency.

## RHVoice engine

- **Version: 1.16.4**, source in the `RHVoice/` folder, with no logic modifications.
- Language data (HTS voice models, Ukrainian and English modules, dictionaries) are bundled in the
  extension resources (`Extension/Resources/RHVoiceData/`).
- The English module is needed to pronounce Latin-script words in mixed text correctly.
- The `sonic` library is used to time-stretch fast speech.

**Speed invariant:** the maximum reachable rate (curve × accelerator) must stay below the engine
ceiling (`max_rate`). Any change to the curve or accelerator ceiling requires re-verifying this
invariant, otherwise the "speed wall" returns.

## Settings and data

- **Settings snapshot** — a JSON file `SharedSettingsSnapshot.json` in the App Group container
  (`RHVoiceSharedSettings.swift`). It holds the voice catalog, enabled voices, and general/per-voice
  parameters. A `UserDefaults` fallback exists for compatibility with older builds.
- **Personal dictionary** (`PersonalUserDictionary.swift`) — user stress corrections, stored in the
  App Group and applied by the engine. The extension learns about changes via a cross-process Darwin
  notification.

## Shared iOS / macOS code

The `UkrainianVoicesApp/Shared/` folder is shared by both platforms (splitter, settings,
dictionary). The Objective-C++ bridges (`RHVoiceCore` for iOS, `RHVoiceKit` for macOS) are
functionally identical. Platform differences are marked with `#if os(macOS)` / `#if os(iOS)` —
mainly the speed ceiling and container paths.

## CI/CD

`.github/workflows/`:

- **iOS → TestFlight** — XcodeGen generation, build, auto-signing with an App Store Connect key,
  upload to TestFlight.
- **macOS signed** — build, signing with a Developer ID certificate, Apple notarization.

In addition to CI there are local build scripts on the Mac (the primary path; GitHub Actions is a
fallback).
