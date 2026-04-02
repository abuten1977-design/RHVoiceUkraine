#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/ios-unsigned-manual.yml"
LEGACY_WORKFLOW="$ROOT_DIR/.github/workflows/build.yml"
PROJECT_YML="$ROOT_DIR/UkrainianVoicesApp/project.yml"
LIB_DIR="$ROOT_DIR/UkrainianVoicesApp/Extension/Libraries"
VOICES_DIR="$ROOT_DIR/UkrainianVoicesApp/Extension/Resources/Voices"
BUILD_SCRIPT="$ROOT_DIR/scripts/build_ios_device_static.sh"

fail() {
  echo "VALIDATION_FAIL: $*" >&2
  exit 1
}

echo "Checking workflow file exists"
[ -f "$WORKFLOW" ] || fail "workflow missing"
[ -f "$LEGACY_WORKFLOW" ] || fail "build.yml missing"
[ -f "$BUILD_SCRIPT" ] || fail "build script missing"

echo "Checking project file exists"
[ -f "$PROJECT_YML" ] || fail "project.yml missing"

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

echo "Checking build.yml uses fresh iPhone library build path"
grep -q '^  workflow_dispatch:' "$LEGACY_WORKFLOW" || fail "build.yml workflow_dispatch missing"
grep -q '^  cancel-in-progress: true' "$LEGACY_WORKFLOW" || fail "build.yml cancel-in-progress missing"
grep -q 'Build fresh iPhone static libraries' "$LEGACY_WORKFLOW" || fail "build.yml missing fresh iPhone build step"
grep -q 'Inject fresh iPhone libraries' "$LEGACY_WORKFLOW" || fail "build.yml missing fresh iPhone injection"
grep -q 'scripts/build_ios_device_static.sh' "$LEGACY_WORKFLOW" || fail "build.yml missing build script reference"
grep -q 'archivePath build/UkrainianVoices.xcarchive' "$LEGACY_WORKFLOW" || fail "build.yml archivePath missing"
grep -q 'retention-days: 1' "$LEGACY_WORKFLOW" || fail "build.yml retention-days mismatch"

echo "Checking project links to bundled static libraries"
grep -Fq 'LIBRARY_SEARCH_PATHS: "$(SRCROOT)/Extension/Libraries"' "$PROJECT_YML" || fail "library search path mismatch"
grep -Fq 'OTHER_LDFLAGS: "-lRHVoice -lRHVoice_core -lRHVoice_audio"' "$PROJECT_YML" || fail "ldflags mismatch"

echo "Checking local tracked libraries are present for repository integrity"
for lib in libRHVoice.a libRHVoice_core.a libRHVoice_audio.a; do
  [ -f "$LIB_DIR/$lib" ] || fail "missing tracked $lib"
done

echo "VALIDATION_OK"
