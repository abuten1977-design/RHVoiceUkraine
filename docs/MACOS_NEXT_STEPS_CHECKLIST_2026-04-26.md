# macOS Next Steps Checklist (2026-04-26)

## Goal
Get deterministic answer in one run: build is ready or not ready.

## CI Gates (must be green)
1. Run `Build RHVoice Mac`:
   - Must pass `Validate packaged macOS artifact (static gate)`.
2. Run `Build RHVoice Mac (Signed)`:
   - Must pass `Validate signed macOS artifact (static + signature gate)`.

If any gate fails, fix only that failing gate first. Do not jump to runtime tests.

## Real Mac Runtime Gates (after signed artifact)
1. Install fresh artifact into `/Applications/UkrainianVoicesMac.app`.
2. Run:
   - `pluginkit -m -A -D | grep -i com.rhvoice.UkrainianVoices.mac.Extension`
   - `auval -v ausp rhvc RHVo`
   - `say -v "?" | grep -Ei 'rhvoice|anatol|marianna|natalia|volodymyr'`
3. Pass criteria:
   - extension visible in `pluginkit`
   - `auval` returns PASS
   - voices listed in `say -v ?`

## Current Known Failure Pattern
- `pluginkit` can be visible while `auval` fails with `-50`.
- This usually means signed/runtime loading mismatch, not build-structure mismatch.
