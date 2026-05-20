#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/UkrainianVoicesApp"
DERIVED_DATA="$APP_DIR/build_audio"
PROOF_DIR="${RUNNER_TEMP:-/tmp}/task041-proof"
PROOF_SWIFT="$PROOF_DIR/task041_proof.swift"
PROOF_BIN="$PROOF_DIR/task041_proof"
PROOF_LOG="$PROOF_DIR/task041_proof.log"

mkdir -p "$PROOF_DIR"

cat > "$PROOF_SWIFT" <<'SWIFT'
import AVFoundation
import AudioToolbox
import Foundation
import UkrainianVoicesExtensionMac

let groupPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Group Containers/group.rhvoice.UkrainianVoices.shared"
let snapshotPath = "\(groupPath)/SharedSettingsSnapshot.json"

try FileManager.default.createDirectory(atPath: groupPath, withIntermediateDirectories: true)

func writeSnapshot(speed: Double, volume: Double, pitch: Double) throws {
    let json = """
    {
      "enabledVoiceIdentifiers" : [
        "com.rhvoice.UkrainianVoices.anatol"
      ],
      "generalSettings" : {
        "pitch" : \(pitch),
        "rate" : 0.5,
        "sentencePause" : 0,
        "speedMultiplier" : \(speed),
        "volume" : \(volume),
        "wordGap" : 0
      },
      "perVoiceSettings" : {
        "com.rhvoice.UkrainianVoices.anatol" : {
          "settings" : {
            "pitch" : \(pitch),
            "rate" : 0.5,
            "sentencePause" : 0,
            "speedMultiplier" : \(speed),
            "volume" : \(volume),
            "wordGap" : 0
          },
          "useCustomSettings" : true
        }
      },
      "revision" : 41,
      "schemaVersion" : 1,
      "selectedVoiceIdentifier" : "com.rhvoice.UkrainianVoices.anatol",
      "updatedAt" : "2026-05-20T00:00:00Z",
      "voiceCatalog" : [
        {
          "identifier" : "com.rhvoice.UkrainianVoices.anatol",
          "language" : "uk-UA",
          "name" : "Anatol",
          "profileName" : "Anatol",
          "sampleText" : "Привіт! Це тест голосу Анатол."
        }
      ]
    }
    """
    try json.write(toFile: snapshotPath, atomically: true, encoding: .utf8)
}

let desc = AudioComponentDescription(
    componentType: kAudioUnitType_Generator,
    componentSubType: 0,
    componentManufacturer: 0,
    componentFlags: 0,
    componentFlagsMask: 0
)

let au = try UkrainianSpeechSynthesizer(componentDescription: desc, options: [])
guard let tree = au.parameterTree else {
    fputs("PROOF FAIL missing_parameter_tree\n", stderr)
    exit(2)
}

let all = tree.allParameters
print("TREE groups=\(tree.children.map(\.identifier).joined(separator: ",")) params=\(all.map { "\($0.identifier):\($0.address):\($0.minValue)-\($0.maxValue):\($0.unit.rawValue)" }.joined(separator: ","))")

func set(_ id: String, _ value: AUValue) {
    guard let parameter = all.first(where: { $0.identifier == id }) else {
        fputs("PROOF FAIL missing_parameter \(id)\n", stderr)
        exit(2)
    }
    tree.implementorValueObserver(parameter, value)
    parameter.value = value
}

func runCase(_ name: String, ssml: String, appSpeed: Double, appVolume: Double, appPitch: Double) throws {
    try writeSnapshot(speed: appSpeed, volume: appVolume, pitch: appPitch)
    set("rate", 1.0)
    set("volume", 1.0)
    set("pitch", 1.0)
    let voice = au.speechVoices.first!
    let request = AVSpeechSynthesisProviderRequest(ssmlRepresentation: ssml, voice: voice)
    print("PROOF_START \(name) appSpeed=\(appSpeed) appVolume=\(appVolume) appPitch=\(appPitch)")
    au.synthesizeSpeechRequest(request)
    print("PROOF_END \(name)")
}

try runCase("baseline-100-speed-1-volume-1", ssml: "<speak><prosody rate=\"100%\">Привіт, це тест.</prosody></speak>", appSpeed: 1.0, appVolume: 1.0, appPitch: 1.0)
try runCase("baseline-100-speed-0_8", ssml: "<speak><prosody rate=\"100%\">Привіт, це тест.</prosody></speak>", appSpeed: 0.8, appVolume: 1.0, appPitch: 1.0)
try runCase("rotor-200-speed-0_8", ssml: "<speak><prosody rate=\"200%\">Привіт, це тест.</prosody></speak>", appSpeed: 0.8, appVolume: 1.0, appPitch: 1.0)
try runCase("ssml-pitch-plus-50", ssml: "<speak><prosody pitch=\"+50%\">Привіт, це тест.</prosody></speak>", appSpeed: 1.0, appVolume: 1.0, appPitch: 1.0)
try runCase("app-pitch-0_8-fallback", ssml: "<speak>Привіт, це тест.</speak>", appSpeed: 1.0, appVolume: 1.0, appPitch: 0.8)
SWIFT

OBJECT_ROOT="$DERIVED_DATA/Build/Intermediates.noindex/UkrainianVoices.build/Debug/UkrainianVoicesExtensionMac.build/Objects-normal"
OBJECT_DIR="$(find "$OBJECT_ROOT" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
BRIDGE_OBJ="$(find "$DERIVED_DATA/Build/Products/Debug" -name RHVoiceBridge.o -print -quit)"

test -n "$OBJECT_DIR"
test -n "$BRIDGE_OBJ"

swiftc "$PROOF_SWIFT" \
  -I "$DERIVED_DATA/Build/Products/Debug" \
  -F "$DERIVED_DATA/Build/Products/Debug" \
  -Xcc "-fmodule-map-file=$DERIVED_DATA/Build/Intermediates.noindex/GeneratedModuleMaps/RHVoiceBridge.modulemap" \
  -Xcc "-fmodule-map-file=$DERIVED_DATA/Build/Intermediates.noindex/GeneratedModuleMaps/RHVoiceCoreEngine.modulemap" \
  -Xcc "-I$ROOT_DIR/RHVoiceCore/Bridge/PublicHeaders" \
  -Xcc "-I$ROOT_DIR/RHVoiceCore/RHVoice/src/include" \
  -framework RHVoiceKit \
  -lc++ \
  "$OBJECT_DIR/UkrainianSpeechSynthesizer.o" \
  "$OBJECT_DIR/RHVoiceSharedSettings.o" \
  "$OBJECT_DIR/RHVoiceSynthesisRuntime.o" \
  "$OBJECT_DIR/AudioUnitFactory.o" \
  "$BRIDGE_OBJ" \
  -Xlinker -rpath \
  -Xlinker "$DERIVED_DATA/Build/Products/Debug" \
  -o "$PROOF_BIN"

rm -rf /tmp/RHVoiceData "$PROOF_DIR/RHVoiceData"
ln -s "$DERIVED_DATA/Build/Products/Debug/UkrainianVoicesMac.app/Contents/Resources/RHVoiceData" /tmp/RHVoiceData
ln -s "$DERIVED_DATA/Build/Products/Debug/UkrainianVoicesMac.app/Contents/Resources/RHVoiceData" "$PROOF_DIR/RHVoiceData"

"$PROOF_BIN" 2>&1 | tee "$PROOF_LOG"

grep -F "TREE groups=rhvoice" "$PROOF_LOG"
grep -F "PROOF_START baseline-100-speed-1-volume-1" "$PROOF_LOG"
grep -F "PROOF_START baseline-100-speed-0_8" "$PROOF_LOG"
grep -F "PROOF_START rotor-200-speed-0_8" "$PROOF_LOG"
grep -F "PROOF_START ssml-pitch-plus-50" "$PROOF_LOG"
grep -F "PROOF_START app-pitch-0_8-fallback" "$PROOF_LOG"
grep -F "rate=1.00" "$PROOF_LOG"
grep -F "rate=0.80" "$PROOF_LOG"
grep -F "rate=1.60" "$PROOF_LOG"
grep -F "pitch=1.50" "$PROOF_LOG"
grep -F "pitch=0.80" "$PROOF_LOG"
test "$(grep -c "Synthesized" "$PROOF_LOG")" -eq 5

echo "TASK041 ACTIONS PROOF PASSED"
