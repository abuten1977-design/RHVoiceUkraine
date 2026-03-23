//
//  SettingsView.swift
//  PolishVariant
//
//  Экран настроек с 5 параметрами
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var voiceManager = VoiceManager.shared
    
    var body: some View {
        NavigationView {
            Form {
                // MARK: - Voice Selection
                Section(header: Text("Голос")) {
                    NavigationLink(destination: VoiceSelectionView()) {
                        HStack {
                            Text("Обраний голос")
                            Spacer()
                            Text(currentVoiceName)
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                // MARK: - Standard Parameters
                Section(header: Text("Основні параметри")) {
                    // Rate
                    VStack(alignment: .leading) {
                        Text("Швидкість мовлення (Rate): \(String(format: "%.2f", voiceManager.parameters.rate))")
                        Slider(value: Binding(
                            get: { voiceManager.parameters.rate },
                            set: { voiceManager.updateParameter(\.rate, to: $0) }
                        ), in: 0.1...4.0, step: 0.1)
                    }
                    
                    // Pitch
                    VStack(alignment: .leading) {
                        Text("Висота тону (Pitch): \(String(format: "%.2f", voiceManager.parameters.pitch))")
                        Slider(value: Binding(
                            get: { voiceManager.parameters.pitch },
                            set: { voiceManager.updateParameter(\.pitch, to: $0) }
                        ), in: 0.5...2.0, step: 0.1)
                    }
                    
                    // Volume
                    VStack(alignment: .leading) {
                        Text("Гучність (Volume): \(String(format: "%.2f", voiceManager.parameters.volume))")
                        Slider(value: Binding(
                            get: { voiceManager.parameters.volume },
                            set: { voiceManager.updateParameter(\.volume, to: $0) }

                    // Speed Multiplier
                    VStack(alignment: .leading) {
                        HStack {
                            Text("1x")
                                .accessibilityHidden(true)
                            Slider(value: Binding(
                                get: { voiceManager.parameters.speedMultiplier },
                                set: { voiceManager.updateParameter(\.speedMultiplier, to: $0) }
                            ), in: 1.0...5.0, step: 0.5)
                            Text("5x")
                                .accessibilityHidden(true)
                        }
                        .accessibilityElement(children: .combine)
                        Text(String(format: "%.1fx", voiceManager.parameters.speedMultiplier))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Speed multiplier")

                    // Sentence Pause
                    VStack(alignment: .leading) {
                        HStack {
                            Text("0")
                                .accessibilityHidden(true)
                            Slider(value: Binding(
                                get: { Double(voiceManager.parameters.sentencePause) },
                                set: { voiceManager.updateParameter(\.sentencePause, to: Int($0)) }
                            ), in: 0...2000, step: 100)
                            Text("2000")
                                .accessibilityHidden(true)
                        }
                        .accessibilityElement(children: .combine)
                        Text("\(Int(voiceManager.parameters.sentencePause)) ms")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Sentence pause")
                        ), in: 0.0...1.0, step: 0.1)
                    }
                }
                
                // MARK: - Advanced Parameters (Ukraine Specific)
                Section(header: Text("Додаткові параметри (Україна)")) {
                    // Speed
                    VStack(alignment: .leading) {
                        Text("Множитель швидкості (Speed): \(String(format: "%.2f", voiceManager.parameters.speed))")
                        Slider(value: Binding(
                            get: { voiceManager.parameters.speed },
                            set: { voiceManager.updateParameter(\.speed, to: $0) }
                        ), in: 0.5...3.0, step: 0.1)
                    }
                    
                    // Pause Duration
                    VStack(alignment: .leading) {
                        Text("Тривалість пауз (Pause Duration): \(String(format: "%.2f", voiceManager.parameters.pauseDuration))")
                        Slider(value: Binding(
                            get: { voiceManager.parameters.pauseDuration },
                            set: { voiceManager.updateParameter(\.pauseDuration, to: $0) }
                        ), in: 0.2...3.0, step: 0.1)
                    }
                }
                
                // MARK: - Actions
                Section {
                    Button("Скинути налаштування") {
                        voiceManager.resetToDefaults()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Налаштування RHVoice")
        }
    }
    
    private var currentVoiceName: String {
        let identifier = voiceManager.selectedVoiceIdentifier
        if let name = identifier.components(separatedBy: ".").last {
            return name.capitalized
        }
        return "Unknown"
    }
}
