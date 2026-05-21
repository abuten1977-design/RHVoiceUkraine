#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/UkrainianVoicesApp"
DERIVED_DATA="$APP_DIR/build_audio"
PROOF_DIR="${RUNNER_TEMP:-/tmp}/task042-proof"
PROOF_SWIFT="$PROOF_DIR/task042_proof.swift"
PROOF_BIN="$PROOF_DIR/task042_proof"
PROOF_LOG="$PROOF_DIR/task042_proof.log"

mkdir -p "$PROOF_DIR"

cat > "$PROOF_SWIFT" <<'SWIFT'
import AVFoundation
import AudioToolbox
import Foundation
import UkrainianVoicesExtensionMac

let groupPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Group Containers/group.rhvoice.UkrainianVoices.shared"
let snapshotPath = "\(groupPath)/SharedSettingsSnapshot.json"
try FileManager.default.createDirectory(atPath: groupPath, withIntermediateDirectories: true)

let snapshot = """
{
  "enabledVoiceIdentifiers" : [
    "com.rhvoice.UkrainianVoices.anatol"
  ],
  "generalSettings" : {
    "pitch" : 1.0,
    "rate" : 0.5,
    "sentencePause" : 0,
    "speedMultiplier" : 1.0,
    "volume" : 1.0,
    "wordGap" : 0
  },
  "perVoiceSettings" : {},
  "revision" : 42,
  "schemaVersion" : 1,
  "selectedVoiceIdentifier" : "com.rhvoice.UkrainianVoices.anatol",
  "updatedAt" : "2026-05-21T00:00:00Z",
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
try snapshot.write(toFile: snapshotPath, atomically: true, encoding: .utf8)

let desc = AudioComponentDescription(
    componentType: kAudioUnitType_Generator,
    componentSubType: 0,
    componentManufacturer: 0,
    componentFlags: 0,
    componentFlagsMask: 0
)

let au = try UkrainianSpeechSynthesizer(componentDescription: desc, options: [])
let voice = au.speechVoices.first!
let renderBlock = au.internalRenderBlock
let frameCount: AUAudioFrameCount = 512
let frames = UnsafeMutablePointer<Float>.allocate(capacity: Int(frameCount))
defer { frames.deallocate() }

func makeBufferList() -> AudioBufferList {
    AudioBufferList(
        mNumberBuffers: 1,
        mBuffers: AudioBuffer(
            mNumberChannels: 1,
            mDataByteSize: UInt32(Int(frameCount) * MemoryLayout<Float>.size),
            mData: UnsafeMutableRawPointer(frames)
        )
    )
}

func runRenderLoop(name: String, deadlineSeconds: Double = 10.0) -> (firstAudioNs: UInt64, totalFrames: Int, complete: Bool) {
    let start = DispatchTime.now().uptimeNanoseconds
    let deadline = Date().addingTimeInterval(deadlineSeconds)
    var firstAudioNs: UInt64 = 0
    var totalFrames = 0
    var renderCalls = 0
    var complete = false

    while Date() < deadline {
        frames.initialize(repeating: 0, count: Int(frameCount))
        var flags = AudioUnitRenderActionFlags()
        var timestamp = AudioTimeStamp()
        var bufferList = makeBufferList()
        let status = withUnsafeMutablePointer(to: &bufferList) { bufferListPointer in
            renderBlock(&flags, &timestamp, frameCount, 0, bufferListPointer, nil, nil)
        }
        renderCalls += 1
        if status != noErr {
            print("TASK042_FAIL \(name) render_status=\(status)")
            exit(2)
        }

        let producedFrames = Int(bufferList.mBuffers.mDataByteSize) / MemoryLayout<Float>.size
        if producedFrames > 0 {
            var hasAudio = false
            for index in 0..<producedFrames where abs(frames[index]) > 0.00001 {
                hasAudio = true
                break
            }
            totalFrames += producedFrames
            if hasAudio && firstAudioNs == 0 {
                firstAudioNs = DispatchTime.now().uptimeNanoseconds - start
            }
        }

        if flags.contains(.offlineUnitRenderAction_Complete) {
            complete = true
            break
        }
        usleep(1_000)
    }

    print("TASK042_TIMING \(name) firstAudioNs=\(firstAudioNs) totalFrames=\(totalFrames) complete=\(complete ? 1 : 0) renderCalls=\(renderCalls)")
    return (firstAudioNs, totalFrames, complete)
}

func runCase(_ name: String, text: String) {
    let ssml = "<speak>\(text)</speak>"
    let request = AVSpeechSynthesisProviderRequest(ssmlRepresentation: ssml, voice: voice)
    au.synthesizeSpeechRequest(request)
    let result = runRenderLoop(name: name)
    if result.firstAudioNs == 0 || result.firstAudioNs > 400_000_000 || result.totalFrames <= 0 {
        print("TASK042_FAIL \(name) firstAudioNs=\(result.firstAudioNs) totalFrames=\(result.totalFrames)")
        exit(2)
    }
}

runCase("short", text: "тест")
runCase("medium", text: "Це середнє тестове речення для перевірки першого звуку у потоковому синтезі.")
runCase("long", text: Array(repeating: "Це довге повідомлення для перевірки затримки у потоковому синтезі.", count: 12).joined(separator: " "))

let firstLong = AVSpeechSynthesisProviderRequest(
    ssmlRepresentation: "<speak>\(Array(repeating: "Перше довге повідомлення має бути скасоване до завершення.", count: 20).joined(separator: " "))</speak>",
    voice: voice
)
au.synthesizeSpeechRequest(firstLong)
usleep(50_000)
au.cancelSpeechRequest()
usleep(50_000)
let second = AVSpeechSynthesisProviderRequest(ssmlRepresentation: "<speak>Другий чистий тест після скасування.</speak>", voice: voice)
au.synthesizeSpeechRequest(second)
let cancelResult = runRenderLoop(name: "cancel-race")
if cancelResult.firstAudioNs == 0 || cancelResult.totalFrames <= 0 {
    print("TASK042_FAIL cancel-race firstAudioNs=\(cancelResult.firstAudioNs) totalFrames=\(cancelResult.totalFrames)")
    exit(2)
}
print("TASK042_CANCEL_RACE passed firstAudioNs=\(cancelResult.firstAudioNs) totalFrames=\(cancelResult.totalFrames)")
print("TASK042 ACTIONS PROOF PASSED")
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

grep -F "TASK042_TIMING short" "$PROOF_LOG"
grep -F "TASK042_TIMING medium" "$PROOF_LOG"
grep -F "TASK042_TIMING long" "$PROOF_LOG"
grep -F "TASK042_CANCEL_RACE passed" "$PROOF_LOG"
grep -F "TASK042 ACTIONS PROOF PASSED" "$PROOF_LOG"
