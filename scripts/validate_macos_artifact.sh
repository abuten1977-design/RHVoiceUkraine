#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-}"
EXPECTED_TYPE="${2:-ausp}"
EXPECTED_SUBTYPE="${3:-rhvc}"
EXPECTED_MANUFACTURER="${4:-RHVo}"

if [[ -z "$APP_PATH" ]]; then
  echo "Usage: $0 <path-to-app> [type] [subtype] [manufacturer]"
  exit 2
fi

failures=0

note() { echo "[INFO] $*"; }
ok() { echo "[PASS] $*"; }
err() { echo "[FAIL] $*"; failures=$((failures + 1)); }

plist_string_value() {
  local plist="$1"
  local key="$2"
  sed -n "/<key>${key//\//\\/}<\/key>/{n;s/.*<string>\\(.*\\)<\\/string>.*/\\1/p;}" "$plist" | head -n1
}

plist_int_value() {
  local plist="$1"
  local key="$2"
  sed -n "/<key>${key//\//\\/}<\/key>/{n;s/.*<integer>\\([0-9]*\\)<\\/integer>.*/\\1/p;}" "$plist" | head -n1
}

if [[ ! -d "$APP_PATH" ]]; then
  echo "[FAIL] App not found: $APP_PATH"
  exit 1
fi

EXT_PATH="$APP_PATH/Contents/PlugIns/UkrainianVoicesExtensionMac.appex"
if [[ ! -d "$EXT_PATH" ]]; then
  EXT_PATH="$(find "$APP_PATH/Contents/PlugIns" -maxdepth 1 -type d -name "*.appex" | head -n1 || true)"
fi

if [[ -z "$EXT_PATH" || ! -d "$EXT_PATH" ]]; then
  err "No .appex found under $APP_PATH/Contents/PlugIns"
  echo "[SUMMARY] FAIL ($failures issues)"
  exit 1
fi

APP_PLIST="$APP_PATH/Contents/Info.plist"
EXT_PLIST="$EXT_PATH/Contents/Info.plist"

[[ -f "$APP_PLIST" ]] && ok "App plist exists" || err "Missing app plist"
[[ -f "$EXT_PLIST" ]] && ok "Extension plist exists" || err "Missing extension plist"

if [[ -f "$EXT_PLIST" ]]; then
  type_val="$(plist_string_value "$EXT_PLIST" "type")"
  subtype_val="$(plist_string_value "$EXT_PLIST" "subtype")"
  manufacturer_val="$(plist_string_value "$EXT_PLIST" "manufacturer")"
  principal_val="$(plist_string_value "$EXT_PLIST" "NSExtensionPrincipalClass")"
  version_val="$(plist_int_value "$EXT_PLIST" "version")"
  ext_point="$(plist_string_value "$EXT_PLIST" "NSExtensionPointIdentifier")"

  [[ "$type_val" == "$EXPECTED_TYPE" ]] && ok "AudioComponents.type=$type_val" || err "AudioComponents.type expected $EXPECTED_TYPE got ${type_val:-<empty>}"
  [[ "$subtype_val" == "$EXPECTED_SUBTYPE" ]] && ok "AudioComponents.subtype=$subtype_val" || err "AudioComponents.subtype expected $EXPECTED_SUBTYPE got ${subtype_val:-<empty>}"
  [[ "$manufacturer_val" == "$EXPECTED_MANUFACTURER" ]] && ok "AudioComponents.manufacturer=$manufacturer_val" || err "AudioComponents.manufacturer expected $EXPECTED_MANUFACTURER got ${manufacturer_val:-<empty>}"
  [[ "$ext_point" == "com.apple.AudioUnit" ]] && ok "NSExtensionPointIdentifier=$ext_point" || err "NSExtensionPointIdentifier expected com.apple.AudioUnit got ${ext_point:-<empty>}"
  [[ "${principal_val:-}" == *AudioUnitFactory* ]] && ok "Principal class looks valid: $principal_val" || err "Principal class missing AudioUnitFactory (${principal_val:-<empty>})"
  [[ -n "$version_val" ]] && ok "AudioComponents.version=$version_val" || err "AudioComponents.version missing"
fi

if [[ -d "$APP_PATH/Contents/Frameworks/RHVoiceKit.framework/Versions" ]]; then
  if [[ -L "$APP_PATH/Contents/Frameworks/RHVoiceKit.framework/Versions/Current" ]]; then
    ok "RHVoiceKit.framework Versions/Current is symlink"
  else
    err "RHVoiceKit.framework Versions/Current is not symlink"
  fi
fi

double_dot="$(find "$APP_PATH" -type f -name "libRHVoice..dylib" -o -name "libRHVoice_core..dylib" -o -name "libRHVoice_audio..dylib" | wc -l | tr -d ' ')"
if [[ "${double_dot:-0}" -gt 0 ]]; then
  note "Found $double_dot double-dot dylib entries (legacy compatibility links)"
else
  ok "No double-dot dylib files found"
fi

if find "$APP_PATH" -type d -name RHVoiceData | grep -q .; then
  ok "RHVoiceData directory exists in bundle"
else
  note "RHVoiceData not found in bundle (may be loaded from App Group)"
fi

note "Extension path: $EXT_PATH"

if [[ "$failures" -gt 0 ]]; then
  echo "[SUMMARY] FAIL ($failures issues)"
  exit 1
fi

echo "[SUMMARY] PASS"
