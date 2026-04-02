#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/ios-unsigned-manual.yml"
LEGACY_WORKFLOW="$ROOT_DIR/.github/workflows/build.yml"
PROJECT_YML="$ROOT_DIR/UkrainianVoicesApp/project.yml"
LIB_DIR="$ROOT_DIR/UkrainianVoicesApp/Extension/Libraries"
VOICES_DIR="$ROOT_DIR/UkrainianVoicesApp/Extension/Resources/Voices"

fail() {
  echo "VALIDATION_FAIL: $*" >&2
  exit 1
}

echo "Checking workflow file exists"
[ -f "$WORKFLOW" ] || fail "workflow missing"
[ -f "$LEGACY_WORKFLOW" ] || fail "build.yml missing"

echo "Checking project file exists"
[ -f "$PROJECT_YML" ] || fail "project.yml missing"

echo "Checking static libraries exist"
for lib in libRHVoice.a libRHVoice_core.a libRHVoice_audio.a; do
  [ -f "$LIB_DIR/$lib" ] || fail "missing $lib"
done

echo "Checking voices directory exists"
[ -d "$VOICES_DIR" ] || fail "voices directory missing"
find "$VOICES_DIR" -maxdepth 2 -type f | grep -q . || fail "voices files missing"

echo "Checking workflow trigger and resource controls"
grep -q '^  workflow_dispatch:' "$WORKFLOW" || fail "workflow_dispatch missing"
grep -q '^  cancel-in-progress: true' "$WORKFLOW" || fail "cancel-in-progress missing"
grep -q '^          retention-days: 1$' "$WORKFLOW" || fail "retention-days is not 1"

echo "Checking workflow uses unsigned archive path"
grep -q 'archivePath build/UkrainianVoices.xcarchive' "$WORKFLOW" || fail "archivePath missing"
grep -q 'CODE_SIGNING_ALLOWED=NO' "$WORKFLOW" || fail "CODE_SIGNING_ALLOWED=NO missing"
grep -q 'generic/platform=iOS' "$WORKFLOW" || fail "generic iOS destination missing"

echo "Checking build.yml uses manual-only tracked-libs path"
grep -q '^  workflow_dispatch:' "$LEGACY_WORKFLOW" || fail "build.yml workflow_dispatch missing"
grep -q '^  cancel-in-progress: true' "$LEGACY_WORKFLOW" || fail "build.yml cancel-in-progress missing"
grep -q 'Verify tracked iPhone libraries and voices' "$LEGACY_WORKFLOW" || fail "build.yml still missing tracked library verification"
grep -q 'archivePath build/UkrainianVoices.xcarchive' "$LEGACY_WORKFLOW" || fail "build.yml archivePath missing"
grep -q 'retention-days: 1' "$LEGACY_WORKFLOW" || fail "build.yml retention-days mismatch"

echo "Checking project links to bundled static libraries"
grep -Fq 'LIBRARY_SEARCH_PATHS: "$(SRCROOT)/Extension/Libraries"' "$PROJECT_YML" || fail "library search path mismatch"
grep -Fq 'OTHER_LDFLAGS: "-lRHVoice -lRHVoice_core -lRHVoice_audio"' "$PROJECT_YML" || fail "ldflags mismatch"

echo "Checking candidate library hashes"
actual_rhvoice="$(sha256sum "$LIB_DIR/libRHVoice.a" | awk '{print $1}')"
actual_core="$(sha256sum "$LIB_DIR/libRHVoice_core.a" | awk '{print $1}')"
actual_audio="$(sha256sum "$LIB_DIR/libRHVoice_audio.a" | awk '{print $1}')"
[ "$actual_rhvoice" = "198ed2a99c1f986110d3ec2bdda8dd35ddd2da102937c7f924894ee7fba545ed" ] || fail "libRHVoice.a hash mismatch"
[ "$actual_core" = "aae6e5802c00259991fa356a529849a3adf8f1ee6013f98430eabdbc45f39a68" ] || fail "libRHVoice_core.a hash mismatch"
[ "$actual_audio" = "6913a5929b3ff454c3db42f53212842d501d40ad773252e8b865fa299d2251e5" ] || fail "libRHVoice_audio.a hash mismatch"

echo "Checking Mach-O archive format"
file "$LIB_DIR/libRHVoice.a" "$LIB_DIR/libRHVoice_core.a" "$LIB_DIR/libRHVoice_audio.a" | grep -q 'arm64' || fail "libraries are not arm64 Mach-O archives"

echo "VALIDATION_OK"
