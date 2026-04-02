#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${1:-$ROOT_DIR/build_ios_device_manual}"
RHVOICE_SRC="$ROOT_DIR/RHVoice/src"
SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)"
RHVOICE_VERSION="$(git -C "$ROOT_DIR/RHVoice" describe --tags --always 2>/dev/null || echo 1.2.2)"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cat > "$RHVOICE_SRC/include/core/config.h" <<EOF
#pragma once

#ifndef RHVOICE_GLOBAL_CONFIG_INCLUDED
#define RHVOICE_GLOBAL_CONFIG_INCLUDED
#define ENABLE_SONIC 0
#define ENABLE_PKG 0

const char VERSION[] = "$RHVOICE_VERSION";
#endif
EOF

cat > "$RHVOICE_SRC/core/config.h" <<'EOF'
const char CONFIG_PATH[] = "";
const char DATA_PATH[] = "";
EOF

CXXFLAGS=(
  -arch arm64
  -isysroot "$SDKROOT"
  -miphoneos-version-min=13.0
  -std=c++11
  -stdlib=libc++
  -DRHVOICE_STATIC
  -I"$RHVOICE_SRC/include"
  -I"$RHVOICE_SRC/hts_engine"
  -I"$ROOT_DIR/RHVoice/external/libs/boost/include"
)

for dep_dir in "$RHVOICE_SRC/third-party"/*; do
  if [ -d "$dep_dir" ]; then
    CXXFLAGS+=(-I"$dep_dir")
  fi
done

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

core_sources=()
while IFS= read -r src; do
  core_sources+=("$src")
done < <(find "$RHVOICE_SRC/core" -maxdepth 1 -name '*.cpp' ! -name 'emoji_data.cpp' ! -name 'unidata.cpp' | sort)

audio_sources=()
while IFS= read -r src; do
  audio_sources+=("$src")
done < <(find "$RHVOICE_SRC/audio" -maxdepth 1 -name '*.cpp' | sort)

lib_sources=()
while IFS= read -r src; do
  lib_sources+=("$src")
done < <(find "$RHVOICE_SRC/lib" -maxdepth 1 -name '*.cpp' | sort)

build_archive libRHVoice_core.a "${core_sources[@]}"
build_archive libRHVoice_audio.a "${audio_sources[@]}"
build_archive libRHVoice.a "${lib_sources[@]}"

echo "Built iPhone static libraries in $BUILD_DIR"
ls -lh "$BUILD_DIR"/libRHVoice*.a
