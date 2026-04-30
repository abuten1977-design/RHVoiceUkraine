#!/bin/bash
set -euo pipefail

IDENTITY="${IDENTITY:-135E29BED25E9472304FF2742D857C47A185B30E}"
KEYCHAIN="${KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
APP_ROOT="${APP_ROOT:-$HOME/Projects/RHVoiceUkraine/UkrainianVoicesApp}"
APP="$APP_ROOT/build_debug_audio_unit_nosign/Build/Products/Debug/UkrainianVoicesMac.app"
EXT="$APP/Contents/PlugIns/UkrainianVoicesExtensionMac.appex"
FW="$APP/Contents/Frameworks"
LIB_SRC="$APP_ROOT/Extension/Libraries"
VOICES_SRC="$APP_ROOT/Extension/Resources/Voices"
VOICES_DST="$EXT/Contents/Resources/Voices"
APP_ENT="$APP_ROOT/App/App.entitlements"
EXT_ENT="$APP_ROOT/Extension/Extension.entitlements"
BUNDLE_ID="com.rhvoice.UkrainianVoices.mac.Extension"

for p in "$KEYCHAIN" "$APP" "$EXT" "$LIB_SRC" "$VOICES_SRC" "$APP_ENT" "$EXT_ENT"; do
  [ -e "$p" ] || { echo "Missing: $p"; exit 1; }
done

mkdir -p "$FW"
for lib in libRHVoice_core.dylib libRHVoice_audio.dylib libRHVoice.dylib; do
  cp -f "$LIB_SRC/$lib" "$FW/$lib"
  chmod 755 "$FW/$lib"
done

mkdir -p "$EXT/Contents/Resources"
rm -rf "$VOICES_DST"
cp -r "$VOICES_SRC" "$VOICES_DST"
echo "Extension voices copied: $(find "$VOICES_DST" -type f | wc -l) files"

echo "Using identity: $IDENTITY"
security find-identity -v -p codesigning | grep "$IDENTITY" || {
  echo "Identity not found in keychain"
  exit 1
}

read -rsp "macOS login password: " KC_PASS
echo

security unlock-keychain -p "$KC_PASS" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KEYCHAIN"

echo "Signing RHVoice dylibs..."
codesign --force --keychain "$KEYCHAIN" --timestamp=none --sign "$IDENTITY" "$FW/libRHVoice_core.dylib"
codesign --force --keychain "$KEYCHAIN" --timestamp=none --sign "$IDENTITY" "$FW/libRHVoice_audio.dylib"
codesign --force --keychain "$KEYCHAIN" --timestamp=none --sign "$IDENTITY" "$FW/libRHVoice.dylib"

echo "Signing extension..."
codesign --force --keychain "$KEYCHAIN" --timestamp=none --sign "$IDENTITY" --entitlements "$EXT_ENT" "$EXT"

echo "Signing app..."
codesign --force --keychain "$KEYCHAIN" --timestamp=none --sign "$IDENTITY" --entitlements "$APP_ENT" "$APP"

echo "Verifying app..."
codesign --verify --deep --strict --verbose=2 "$APP"

echo "App signature:"
codesign -dv "$APP" 2>&1 | sed -n "1,30p"

echo "Extension signature:"
codesign -dv "$EXT" 2>&1 | sed -n "1,30p"

echo "spctl:"
spctl -a -vv "$APP" 2>&1 || true

echo "pluginkit:"
pluginkit -m -A -D -i "$BUNDLE_ID" || true
