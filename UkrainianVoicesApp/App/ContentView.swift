//  ContentView.swift — Ukrainian Voices settings UI
//  Copyright (C) 2026 Andriy Butenko — MIT

import SwiftUI
import AVFoundation

private let appGroup = "group.rhvoice.UkrainianVoices.shared"
private let defaults = UserDefaults(suiteName: appGroup) ?? .standard
private let enabledVoiceIdentifiersKey = "enabledVoiceIdentifiers"
private let selectedVoiceIdentifierKey = "selectedVoiceIdentifier"

private struct VoiceDefinition: Identifiable, Hashable {
    let name: String
    let identifier: String
    let language: String
    let sampleText: String

    var id: String { identifier }
}

private let voiceCatalog: [VoiceDefinition] = [
    .init(name: "Anatol", identifier: "com.rhvoice.UkrainianVoices.anatol", language: "uk-UA", sampleText: "Привіт! Це тест голосу Анатол."),
    .init(name: "Marianna", identifier: "com.rhvoice.UkrainianVoices.marianna", language: "uk-UA", sampleText: "Привіт! Це тест голосу Маріанна."),
    .init(name: "Natalia", identifier: "com.rhvoice.UkrainianVoices.natalia", language: "uk-UA", sampleText: "Привіт! Це тест голосу Наталія."),
    .init(name: "Volodymyr", identifier: "com.rhvoice.UkrainianVoices.volodymyr", language: "uk-UA", sampleText: "Привіт! Це тест голосу Володимир."),
    .init(name: "Alan", identifier: "com.rhvoice.UkrainianVoices.alan", language: "en-US", sampleText: "Hello! This is a test of Alan voice."),
    .init(name: "Victoria", identifier: "com.rhvoice.UkrainianVoices.victoria", language: "en-US", sampleText: "Hello! This is a test of Victoria voice.")
]

struct ContentView: View {
    @AppStorage("rate", store: defaults) private var rate: Double = 0.5
    @AppStorage("volume", store: defaults) private var volume: Double = 1.0
    @AppStorage("speedMultiplier", store: defaults) private var speedMultiplier: Double = 1.0
    @AppStorage("sentencePause", store: defaults) private var sentencePause: Double = 0
    @AppStorage(selectedVoiceIdentifierKey, store: defaults) private var selectedVoiceIdentifier: String = "com.rhvoice.UkrainianVoices.marianna"

    @State private var testText = "Привіт! Це тест українського голосу."
    @State private var enabledVoiceIdentifiers: Set<String> = []
    @State private var isSpeaking = false
    @State private var statusMessage = ""

    private let synth = AVSpeechSynthesizer()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ukrainian Voices")
                .font(.largeTitle).bold()
                .padding([.horizontal, .top])
                .padding(.bottom, 8)

            List {
                Section("Voices") {
                    ForEach(groupedVoices, id: \.0) { language, voices in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(language)
                                .font(.headline)
                            ForEach(voices) { voice in
                                voiceRow(voice)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Speech") {
                    sliderRow(title: "Speech rate", value: $rate, range: 0...1, step: 0.05, valueText: String(format: "%.0f%%", rate * 100))
                    sliderRow(title: "Volume", value: $volume, range: 0...1, step: 0.05, valueText: String(format: "%.0f%%", volume * 100))
                    sliderRow(title: "Speed multiplier", value: $speedMultiplier, range: 1...5, step: 0.5, valueText: String(format: "%.1fx", speedMultiplier))
                    sliderRow(title: "Sentence pause", value: $sentencePause, range: 0...2000, step: 100, valueText: "\(Int(sentencePause)) ms")
                }

                Section("Preview") {
                    TextField("Text to speak", text: $testText)
                    HStack {
                        Button(isSpeaking ? "Stop" : "Preview selected voice") {
                            isSpeaking ? stopSpeaking() : previewSelectedVoice()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Apply voices to system") {
                            applyVoicesToSystem()
                        }
                        .buttonStyle(.bordered)
                    }
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                Section("How it works") {
                    Text("1. Turn on the RHVoice voices you want.")
                    Text("2. Press Apply voices to system.")
                    Text("3. Then use Test or open VoiceOver Utility.")
                }
            }
        }
        .frame(minWidth: 560, minHeight: 700)
        .onAppear(perform: loadVoiceState)
    }

    private var groupedVoices: [(String, [VoiceDefinition])] {
        Dictionary(grouping: voiceCatalog, by: { $0.language })
            .sorted { $0.key < $1.key }
    }

    @ViewBuilder
    private func voiceRow(_ voice: VoiceDefinition) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(isOn: binding(for: voice.identifier)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(voice.name).fontWeight(.medium)
                        Text(voice.identifier)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)

                if selectedVoiceIdentifier == voice.identifier {
                    Text("Selected")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            HStack {
                Button("Use for preview") {
                    selectedVoiceIdentifier = voice.identifier
                    if !enabledVoiceIdentifiers.contains(voice.identifier) {
                        enabledVoiceIdentifiers.insert(voice.identifier)
                        persistVoiceState()
                    }
                    statusMessage = "Selected voice: \(voice.name)"
                }
                .buttonStyle(.bordered)

                Button("Test") {
                    previewVoice(voice)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, valueText: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .foregroundColor(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private func binding(for identifier: String) -> Binding<Bool> {
        Binding(
            get: { enabledVoiceIdentifiers.contains(identifier) },
            set: { enabled in
                if enabled {
                    enabledVoiceIdentifiers.insert(identifier)
                } else {
                    enabledVoiceIdentifiers.remove(identifier)
                    if selectedVoiceIdentifier == identifier {
                        selectedVoiceIdentifier = enabledVoiceIdentifiers.first ?? voiceCatalog.first?.identifier ?? identifier
                    }
                }
                persistVoiceState()
            }
        )
    }

    private func loadVoiceState() {
        if let stored = defaults.stringArray(forKey: enabledVoiceIdentifiersKey) {
            enabledVoiceIdentifiers = Set(stored)
        } else {
            enabledVoiceIdentifiers = Set(voiceCatalog.map(\.identifier))
            persistVoiceState()
        }

        if !enabledVoiceIdentifiers.contains(selectedVoiceIdentifier) {
            selectedVoiceIdentifier = enabledVoiceIdentifiers.first ?? voiceCatalog.first?.identifier ?? selectedVoiceIdentifier
        }
    }

    private func persistVoiceState() {
        defaults.set(Array(enabledVoiceIdentifiers).sorted(), forKey: enabledVoiceIdentifiersKey)
        defaults.set(selectedVoiceIdentifier, forKey: selectedVoiceIdentifierKey)
    }

    private func previewSelectedVoice() {
        guard let voice = voiceCatalog.first(where: { $0.identifier == selectedVoiceIdentifier }) else {
            statusMessage = "Select a voice first."
            return
        }
        previewVoice(voice, overrideText: testText)
    }

    private func previewVoice(_ voice: VoiceDefinition, overrideText: String? = nil) {
        guard let systemVoice = AVSpeechSynthesisVoice(identifier: voice.identifier) else {
            statusMessage = "\(voice.name) is not registered in the system yet. Press Apply voices to system first."
            return
        }

        let text = (overrideText?.isEmpty == false) ? overrideText! : voice.sampleText
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = systemVoice
        utterance.rate = Float(rate) * Float(speedMultiplier) * 0.5
        utterance.volume = Float(volume)
        isSpeaking = true
        statusMessage = "Previewing \(voice.name)."
        synth.speak(utterance)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            isSpeaking = false
        }
    }

    private func stopSpeaking() {
        synth.stopSpeaking(at: .immediate)
        isSpeaking = false
        statusMessage = "Preview stopped."
    }

    private func applyVoicesToSystem() {
        persistVoiceState()
        AVSpeechSynthesisProviderVoice.updateSpeechVoices()
        statusMessage = enabledVoiceIdentifiers.isEmpty
            ? "No RHVoice voices are enabled right now."
            : "System voice list updated. Enabled: \(enabledVoiceIdentifiers.count)."
    }
}
