# Challenges, Solutions, and Open Risks

This is the most useful file for an analysis agent looking for latent problems.
Each item: the problem, the real root cause (confirmed in code/data, not
guessed), the fix, and residual risk.

Documented commit `f9c1c6c0`, branch `ci/macos-gates-2026-04-26`.

---

## 1. Architectural pivot: C engine as a library vs. compiled in‑target

**Problem.** Early attempts linked RHVoice as prebuilt `.dylib`/`.a`. This broke
across platforms (paths, signing, portability), repeatedly.

**Resolution.** RHVoice C/C++ is compiled **as part of the build target**:
macOS in‑target in `RHVoiceKitMac`; iOS via the SwiftPM package `RHVoiceCore`
(`RHVoiceBridge`). A short‑lived "special framework" macOS experiment worked on
macOS but did not port to iOS, confirming the in‑target/SwiftPM approach.

**Residual risk / rule.** Reverting to `.dylib`/`.a` is a regression. Engine
build knobs must be kept **in sync across two places** — `project.yml`
(macOS) and `RHVoiceCore/Package.swift` (iOS). Drift here has caused bugs.

---

## 2. The engine speed wall (the "everything fast sounds the same" plateau)

**Problem.** Above a point, increasing speed produced no audible change;
accelerator was inaudible at high rates.

**Root cause (confirmed by numbers + source).** `RHVoice/src/core/params.cpp`
clamps effective `max_rate` to `MAX_MAX_RATE`, historically hard‑coded to **5**.
Sonic received the already‑clipped rate, so it could not speed audio up. Not the
Swift formula — a wall in the C engine.

**Resolution.** `MAX_MAX_RATE` made configurable via `RHVOICE_MAX_MAX_RATE`;
set to 20 on both platforms (`project.yml` for macOS, `Package.swift` for iOS),
plus `MAX_RATE=20` and `RHVoice.conf languages.ukrainian.max_rate=20`,
`min_sonic_rate=1`. Sonic now time‑stretches for fast speech.

**Invariant (must hold forever).** max reachable `finalRate` = (curve max 4.5)
× (accelerator max 4.0) = 18.0 **< 20** ceiling. If a future change raises the
curve top or accelerator max past the ceiling, the plateau returns. Re‑check on
any speed change.

---

## 3. iOS vs macOS VoiceOver rate scale (the worst trap)

**Problem.** A curve proven on macOS was ported to iOS and made speed *worse*
(usable range squeezed into rotor ~15–20%; max ≈ normal speed, never fast).

**Root cause (confirmed by real device logs, task‑018).** macOS VoiceOver sends
SSML `prosody rate` ~100→**424%**; iOS VoiceOver sends only ~**10→100%**.
Apple’s documented prosody range is ~20–200%, **100% = normal, not maximum**.
The ported macOS curve was anchored at 424, so on iOS it never reached the fast
branch — the whole rotor mapped to ≤1.0×.

**Resolution.** iOS‑appropriate curve: rotor 0%→0.25×, 50%→1.0×, 100%→4.0×
(max 4.5×), independent of the macOS 424 anchor. Verified by ear via the rotor;
`PARAMS` os_log used for measurement.

**Residual risk.** (a) Measurement via the rotor is noisy — VoiceOver announces
every step while scrolling, and the rotor wraps (low end can jump to 100). The
*curve* is correct; the wrap is a VoiceOver input quirk, not our bug.
(b) The macOS curve was also changed by the unification — **macOS speed feel is
no longer the previously approved one** (open verification item §Open risks).

---

## 4. App Group settings sync — uncertainty then clarity

**Problem.** It looked like nothing from the app reached the iOS extension; an
early hypothesis blamed App Group provisioning.

**Findings (confirmed).** App Group **works**: the entitlement
`com.apple.security.application-groups = group.rhvoice.UkrainianVoices.shared`
is present and provisioned in **both** iOS App IDs (verified by decoding the
signed `embedded.mobileprovision` of the app and the extension). Volume changes
from the app were audible → settings do cross.

**Real issue & fix.** `effectiveSettings(for:)` only returns per‑voice values
when `useCustomSettings == true`; defaults made it false, so per‑voice edits
were ignored. Changed `RHVoicePerVoiceSettings.inherited` and the legacy
defaults fallback to `useCustomSettings = true`, and the simplified UI always
persists per‑voice with that flag.

**Residual risk.** `loadSnapshot` prefers a JSON file in the App Group
container and falls back to a UserDefaults mirror; both are written on save.
Schema evolution must keep `init(from:)` tolerant (it currently defaults missing
`pitch` and `wordGap`). Adding fields without a default would break old
snapshots.

---

## 5. Volume/pitch double control

**Problem.** App had sliders for speech rate/volume/pitch that duplicated
VoiceOver’s own controls and could fight them.

**Resolution.** Those sliders were removed; the extension forces
`effectiveVolume = ssmlVolume` and `effectivePitch = 1.0` so VoiceOver fully
owns volume/pitch. The app keeps only what VoiceOver cannot express:
Accelerator, Sentence pause, Word gap.

**Residual risk.** If the stored `volume`/`pitch` for a voice were ever applied
again by accident, VoiceOver’s values would be distorted. The neutralization is
in two spots (model defaults to 1.0 + extension hard‑codes pass‑through); keep
both.

---

## 6. SSML corruption by pause insertion

**Problem.** Sentence pause inserted `<break>` via a regex over the whole SSML;
a `.`/`,` inside an attribute (`rate="42.5%"`) or a number got matched and a
`<break>` was injected inside a tag → invalid SSML.

**Resolution.** `applyTextBreaks` scans char‑by‑char, copies `<…>` tags
verbatim, inserts breaks only in text segments, and treats digit‑dot‑digit as a
decimal (not a sentence end). Verified on text containing attributes, a decimal
number, and a pre‑existing `<break>`.

**Residual risk.** The scanner is a hand‑rolled mini‑parser, not a real XML
parser. Edge cases to review: CDATA, comments, `<` in text content, attribute
values containing `>`, malformed SSML. Worth fuzzing.

---

## 7. Accessibility: duplicated slider announcements

**Problem.** Each slider was announced twice by VoiceOver (visible `Text` label
+ slider with the same `accessibilityLabel`).

**Resolution.** In `sliderRow`, the visible label row is
`.accessibilityHidden(true)`; the `Slider` carries the single label/value/hint.
Applies to all sliders.

---

## 8. Latin words read as transliteration

Covered in PARAMS_AND_BUILD.md §5. Root cause confirmed in `language.cpp`
(`get_second_language`) / `ukrainian.cpp` (`untranslit_fst`). Fix: bundle the
English module + `bilingual=English` + existing `english_phone_mapping.fst`.

**Residual risk.** Bundle size increased. Pronunciation is the Ukrainian voice
approximating English phones — recognizable, not native. Mixed‑script edge
cases and Ukrainian words misdetected as English should be spot‑checked.

---

## 9. Code signing / distribution

- iOS: solved with an App Store Connect API key (`.p8`, non‑expiring) in GitHub
  Secrets; CI does automatic signing and uploads to TestFlight via `altool`.
- macOS: `Developer ID Application: Andriy Butenko (5NNZPP8CRR)`. Notarization
  reliably hangs in CI and is **not** required for local testing (strip
  quarantine). Treat a red notarization step as expected, not a failure.

---

## Open risks (verify these)

1. **macOS speed feel changed.** The speed curve was unified; macOS no longer
   uses the previously hand‑approved curve, and macOS ceiling was raised
   12→20. Needs an on‑device macOS listening check; don’t assume unchanged.
2. **iOS rate scale assumption.** The iOS curve assumes VoiceOver delivers
   ~0–100% (with headroom to 200). If some iOS/VoiceOver versions deliver a
   different range, the top of the curve may be unreachable or saturate early.
3. **Engine‑ceiling invariant** (CHALLENGES §2): any future change to curve top
   or accelerator max must keep `max finalRate < MAX_MAX_RATE`.
4. **Cross‑platform define drift:** `RHVOICE_MAX_MAX_RATE` / `MAX_RATE` exist in
   two build systems (`project.yml`, `Package.swift`). They must stay equal.
5. **Hand‑rolled SSML scanner** (§6): not a real parser; fuzz for malformed
   SSML, comments, CDATA, stray `<`/`>`.
6. **`build-mac.yml` (unsigned) is red** independently of the signed build;
   confirm it is not masking a real macOS regression (signed build compiling is
   the real signal).
7. **Word gap is increase‑only**; cannot tighten below RHVoice’s natural
   spacing without an engine change.
8. **Rotor measurement noise:** any future rate tuning should be validated by
   ear through the rotor or via the `PARAMS` log at steady state, not by
   scrolling‑capture (which logs every transient value and the wrap‑to‑100).
