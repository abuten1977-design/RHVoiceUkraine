#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="build_debug_audio_unit_nosign"
APP="$BUILD_DIR/Build/Products/Debug/UkrainianVoicesMac.app"
EXT="$APP/Contents/PlugIns/UkrainianVoicesExtensionMac.appex"
FRAMEWORKS="$APP/Contents/Frameworks"

rm -rf "$BUILD_DIR"
xcodebuild -project UkrainianVoicesMac.xcodeproj \
  -scheme UkrainianVoicesMac \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build

mkdir -p "$FRAMEWORKS"
for lib in libRHVoice.dylib libRHVoice_core.dylib libRHVoice_audio.dylib; do
  cp -f "Extension/Libraries/$lib" "$FRAMEWORKS/$lib"
  chmod 755 "$FRAMEWORKS/$lib"
done

plutil -lint "$EXT/Contents/Info.plist" >/dev/null
echo "---DEPS---"
otool -L "$EXT/Contents/MacOS/UkrainianVoicesExtensionMac"
echo "---BUNDLE---"
find "$APP" -maxdepth 4 \( -name Frameworks -o -name PlugIns -o -name Voices -o -name "*.dylib" \)
