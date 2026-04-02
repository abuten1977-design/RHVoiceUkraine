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

mapfile -t core_sources < <(find "$RHVOICE_SRC/core" -maxdepth 1 -name '*.cpp' | sort)
mapfile -t audio_sources < <(find "$RHVOICE_SRC/audio" -maxdepth 1 -name '*.cpp' | sort)
mapfile -t lib_sources < <(find "$RHVOICE_SRC/lib" -maxdepth 1 -name '*.cpp' | sort)

build_archive libRHVoice_core.a "${core_sources[@]}"
build_archive libRHVoice_audio.a "${audio_sources[@]}"
build_archive libRHVoice.a "${lib_sources[@]}"

echo "Built iPhone static libraries in $BUILD_DIR"
ls -lh "$BUILD_DIR"/libRHVoice*.a
