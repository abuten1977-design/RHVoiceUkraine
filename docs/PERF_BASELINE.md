# RHVoice iOS performance gates

Updated: 2026-07-31, task 207.

## Mandatory pre-release checks

1. Run `RHVoicePipelineSplitterTests`. The normalizer benchmark cases are:
   - one typed character, 1,000 calls;
   - normal sentence with a number and date, 1,000 calls;
   - approximately 1,000-character paragraph, 100 calls.
2. A change that makes any saved baseline slower by more than 10% is a release
   blocker until investigated.
3. For changes on the speech path, connect a real iPhone and collect
   `LATENCY_DIAG` through `idevicesyslog`. Read the standard 24-line control
   text and a 30-character typing sequence. Do not release if the comparable
   device timing is more than 15% worse than the accepted build 204 baseline.
4. Confirm all unit tests, iOS/macOS builds, and `say -v '?'` (four Ukrainian
   voices) before TestFlight.

## Current normalizer baseline

The fast path is structural: the abbreviation dictionary returns before regex
work when the text is shorter than a key or has no candidate initial letter.
Otherwise it uses at most two precompiled expressions (Cyrillic and Latin),
rebuilt only after a dictionary change. The unit test `testAbbreviationDictionaryMatcherKeepsTypingPathFastWithHundredEntries` guards the 1,000-character-entry typing case.

## Device evidence

Task 207 initial device: iPhone 17, identifier `D125FE2D-59F6-513D-8676-21C31A8A29EF`, current TestFlight build 206. The app is visible over USB. A Release TestFlight build cannot run the debug-only `--self-test` diagnostic; the real VoiceOver control-text measurement therefore remains a human speech gate, captured with:

```sh
idevicesyslog --no-colors -u 00008150-0016155A0293401C -m LATENCY_DIAG
```

It must be recorded for the candidate build before external distribution.
