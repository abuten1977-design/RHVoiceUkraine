#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${1:-$ROOT_DIR/build_ios_device_manual}"
RHVOICE_SRC="$ROOT_DIR/RHVoice/src"
SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

CXXFLAGS=(
  -arch arm64
  -isysroot "$SDKROOT"
  -miphoneos-version-min=13.0
  -std=c++11
  -stdlib=libc++
  -DRHVOICE_STATIC
  -I"$RHVOICE_SRC/include"
  -I"$ROOT_DIR/RHVoice/src/third-party/utf8"
)

build_archive() {
  local name="$1"
  shift
  local out="$BUILD_DIR/$name"
  local objects=()

  for src in "$@"; do
    local obj="$BUILD_DIR/$(basename "${src%.cpp}").o"
    clang++ "${CXXFLAGS[@]}" -c "$src" -o "$obj"
    objects+=("$obj")
  done

  rm -f "$out"
  ar rcs "$out" "${objects[@]}"
}

collect_sources() {
  local dir="$1"
  local -n out_ref="$2"
  out_ref=()

  while IFS= read -r src; do
    out_ref+=("$src")
  done < <(find "$dir" -maxdepth 1 -name '*.cpp' | sort)
}

collect_sources "$RHVOICE_SRC/core" core_sources
collect_sources "$RHVOICE_SRC/audio" audio_sources
collect_sources "$RHVOICE_SRC/lib" lib_sources

build_archive libRHVoice_core.a "${core_sources[@]}"
build_archive libRHVoice_audio.a "${audio_sources[@]}"
build_archive libRHVoice.a "${lib_sources[@]}"

echo "Built iPhone static libraries in $BUILD_DIR"
ls -lh "$BUILD_DIR"/libRHVoice*.a
