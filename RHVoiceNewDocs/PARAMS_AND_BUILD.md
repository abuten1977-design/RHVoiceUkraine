# Parameter Pipeline, Speed Curve, Bilingual, Build & CI

Documented commit `f9c1c6c0`, branch `ci/macos-gates-2026-04-26`.

## 1. Parameter pipeline (per synthesis request)

In `UkrainianSpeechSynthesizer.synthesizeSpeechRequest`:

```
ssmlRatePercent = extractSSMLRatePercent(text)        // VoiceOver prosody rate %
ssmlVolume      = extractSSMLVolume(text)             // VoiceOver volume (dB→linear)
voiceSettings   = loadSnapshot().effectiveSettings(for: voiceId)  // App Group, per-voice

mappedRate   = mapSSMLRatePercentToEngineMultiplier(ssmlRatePercent)
accelerator  = clampAccelerator(voiceSettings.speedMultiplier)     // 1.0…4.0
finalRate    = mappedRate * accelerator
effectiveVolume = ssmlVolume          // app volume NOT applied (VoiceOver owns it)
effectivePitch  = 1.0                 // app pitch  NOT applied (VoiceOver owns it)

sentencePauseMs = clampSentencePause(voiceSettings.sentencePause)  // 0…2000
wordGapMs       = clampWordGap(voiceSettings.wordGap)              // 0…300
synthesisText   = applyTextBreaks(text, sentencePauseMs, wordGapMs) // SSML-safe

engine.synthesize(synthesisText, voice, rate: finalRate,
                   volume: effectiveVolume, pitch: effectivePitch)
```

Telemetry: `os_log` category `params`, message `PARAMS ssmlRatePct=… mappedRate=…
accelerator=… finalRate=… vol=… pitch=… pauseMs=… wordGapMs=… useCustom=…`.
This line is how rate behavior is measured on a real device.

## 2. The speed curve (critical, platform‑specific)

`mapSSMLRatePercentToEngineMultiplier(percent)` — current iOS branch:

```
normalizedPercent = max(0, percent)
if normalizedPercent <= 100:
    return pow(4.0, (normalizedPercent - 50.0) / 50.0)
else:
    progress = min((normalizedPercent - 100.0) / 100.0, 1.0)   // iOS: /100
    return 4.0 * pow(1.125, progress)
```

iOS resulting map (rotor → engine multiplier):

| VoiceOver rotor | mappedRate | feel |
|---|---|---|
| 0%   | 0.25 | very slow |
| 25%  | 0.50 | slow |
| 50%  | 1.00 | normal |
| 75%  | 2.00 | fast |
| 100% | 4.00 | very fast |
| ≥200%| 4.50 | max curve output |

macOS uses the same shape but the `>100` branch divides progress by `324`
(legacy macOS VoiceOver scale reaches ~424%). **macOS curve was changed by this
work**; macOS feel differs from the previously hand‑tuned version — flagged as
an open verification item (CHALLENGES §Open risks).

### Why this matters — the scale difference

Real device logs (task‑018) proved **iOS VoiceOver sends `prosody rate` only in
~10–100%**, never the large values macOS sends (macOS: 100→424%). Apple's
documented SSML prosody rate range is ~20–200%, **100% = normal (not max)**. The
earlier bug was porting the macOS curve (anchored at 424%) to iOS, which
compressed the entire iOS rotor range into ≤1.0× (no fast speech at all).

## 3. Engine ceiling (must exceed max reachable)

`RHVoice/src/core/params.cpp`:

```
#ifdef RHVOICE_MAX_MAX_RATE
  const double MAX_MAX_RATE = RHVOICE_MAX_MAX_RATE;
#else
  const double MAX_MAX_RATE = 5;            // historical default = the "speed wall"
#endif
...
max_rate("max_rate", MAX_RATE, 1, MAX_MAX_RATE)   // effective max_rate is clamped to MAX_MAX_RATE
```

Current settings (both platforms): `MAX_RATE=20`, `RHVOICE_MAX_MAX_RATE=20`
(iOS via `RHVoiceCore/Package.swift` commonDefines, macOS via `project.yml`
`GCC_PREPROCESSOR_DEFINITIONS`), plus `RHVoice.conf`
`languages.ukrainian.max_rate=20`, `languages.ukrainian.min_sonic_rate=1`
(Sonic engages from rate ≥ 1 → clean fast speech).

**Invariant that must always hold:** the maximum reachable `finalRate`
( = max curve output × max accelerator = 4.5 × 4.0 = 18.0 ) must be **strictly
below** the engine ceiling (20). 18 < 20 ✔. If MAX_MAX_RATE / max_rate were
lower than 18, high settings would clip and the "everything fast sounds the
same" plateau would return. Any future change to the curve top or the
accelerator max **must** re‑check this invariant.

## 4. Sentence pause & word gap (SSML‑safe)

`applyTextBreaks` (see ARCHITECTURE §4.4). Verified example
(sentencePause=250, wordGap=50):

input: `<speak><prosody rate="42.5%" volume="-3.0dB">Viber 42.5, тест.</prosody><break time='100ms'/> Далі?</speak>`

output keeps `rate="42.5%"`, `volume="-3.0dB"` and the existing
`<break time='100ms'/>` intact; `42.5` is not split; new breaks appear only in
text. Sentence pause range 0…2000 ms; word gap 0…300 ms (0 = off = previous
behavior). Word gap can only *increase* spacing — RHVoice has no native
word‑gap setting and reducing below the engine's natural spacing would need an
engine change.

## 5. Bilingual / Latin words (no transliteration)

Root cause (confirmed in `language.cpp` / `ukrainian.cpp`): if there is no
second language, a Latin word falls through to `ukrainian::decode_as_word` →
`untranslit_fst` → letter‑by‑letter Cyrillic ("Viber" → "Вібер").
`get_second_language()` returns null unless: the per‑language `bilingual`
property is set, `foreign_phone_mapping_fst` exists, and the named language is
loaded.

Fix in place: `languages/English/` bundled; `languages/Ukrainian/language.info`
has `bilingual=English`; `english_phone_mapping.fst` already shipped; global
`enable_bilingual` defaults true. Result: Latin words are spoken with English
pronunciation rendered through the Ukrainian voice (no separate English voice
needed). Shared data tree ⇒ applies to iOS and macOS.

## 6. Build & CI

Xcode project is generated by **XcodeGen** from `UkrainianVoicesApp/project.yml`.
Local builds are not possible on the available Mac (Xcode 15.2 / macOS 13 too
old; Xcode cannot manage iOS 26 devices) — **all builds go through GitHub
Actions**.

Workflows in `.github/workflows/`:

- **`build.yml`** — "Build Signed iOS App and Upload to TestFlight"
  (`workflow_dispatch`). Decodes App Store Connect API key (`.p8`) from secrets
  `ASC_API_KEY_BASE64`, `ASC_KEY_ID`, `ASC_ISSUER_ID`; `xcodebuild archive`
  with automatic signing; `altool --upload-app` → TestFlight. The `.p8` does
  not expire. Build number = `CURRENT_PROJECT_VERSION` (auto‑incremented per run).
- **`build-mac-signed.yml`** — signed macOS: archive/export, manual Developer ID
  signing, signature/static gate, package, pre‑notary artifact, then Apple
  notarization. **Notarization is expected to hang/redden and is NOT a blocker**
  for local testing (clear quarantine with `xattr -dr com.apple.quarantine`).
- `build-mac.yml` (unsigned macOS, secondary; can be red independently),
  `build-ios-synthesizer.yml`, `ios-unsigned-manual.yml`,
  `build-rhvoicekit-*` — auxiliary.

Signing assets:

- iOS: App Store Connect API key (`.p8`) in GitHub Secrets; Xcode automatic
  signing creates Distribution cert + profiles. App Group is provisioned in
  both iOS App IDs (`com.rhvoice.ukraine.app.5NNZPP8CRR` and `.Extension`).
- macOS: `Developer ID Application: Andriy Butenko (5NNZPP8CRR)` in
  `MACOS_*` secrets.

### Build verification quick‑checklist (used before shipping a build)

1. iOS `build.yml` run = success; log shows `UPLOAD SUCCEEDED with no errors`;
   note build number + Delivery UUID.
2. macOS signed run: archive/sign/validate/package/pre‑notary green
   (notarization may be skipped).
3. `git diff` confirms only intended files changed; the speed‑ceiling
   invariant (§3) still holds; macOS not broken (ContentView is shared).
