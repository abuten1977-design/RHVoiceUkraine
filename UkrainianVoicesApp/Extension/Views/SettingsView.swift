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
                            .accessibilityLabel("Швидкість мовлення")
                            .accessibilityValue("\(String(format: "%.2f", voiceManager.parameters.rate))")
                            .accessibilityHint("Змінює швидкість мовлення голосу")
                            .accessibilityAddTraits(.isAdjustable)
                    }
                    
                    // Pitch
                    VStack(alignment: .leading) {
                        Text("Висота тону (Pitch): \(String(format: "%.2f", voiceManager.parameters.pitch))")
                        Slider(value: Binding(
                            get: { voiceManager.parameters.pitch },
                            set: { voiceManager.updateParameter(\.pitch, to: $0) }
                        ), in: 0.5...2.0, step: 0.1)
                            .accessibilityLabel("Висота тону")
                            .accessibilityValue("\(String(format: "%.2f", voiceManager.parameters.pitch))")
                            .accessibilityHint("Змінює висоту тону голосу")
                            .accessibilityAddTraits(.isAdjustable)
                    }
                    
                    // Volume
                    VStack(alignment: .leading) {
                        Text("Гучність (Volume): \(String(format: "%.2f", voiceManager.parameters.volume))")
                        Slider(value: Binding(
                            get: { voiceManager.parameters.volume },
                            set: { voiceManager.updateParameter(\.volume, to: $0) }
                        ), in: 0.0...1.0, step: 0.1)
                            .accessibilityLabel("Гучність")
                            .accessibilityValue("\(String(format: "%.2f", voiceManager.parameters.volume))")
                            .accessibilityHint("Змінює гучність голосу")
                            .accessibilityAddTraits(.isAdjustable)
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
                            .accessibilityLabel("Множитель швидкості")
                            .accessibilityValue("\(String(format: "%.2f", voiceManager.parameters.speed))")
                            .accessibilityHint("Змінює множитель швидкості мовлення")
                            .accessibilityAddTraits(.isAdjustable)
                    }
                    
                    // Pause Duration
                    VStack(alignment: .leading) {
                        Text("Тривалість пауз (Pause Duration): \(String(format: "%.2f", voiceManager.parameters.pauseDuration))")
                        Slider(value: Binding(
                            get: { voiceManager.parameters.pauseDuration },
                            set: { voiceManager.updateParameter(\.pauseDuration, to: $0) }
                        ), in: 0.2...3.0, step: 0.1)
                            .accessibilityLabel("Тривалість пауз")
                            .accessibilityValue("\(String(format: "%.2f", voiceManager.parameters.pauseDuration))")
                            .accessibilityHint("Змінює тривалість пауз між реченнями")
                            .accessibilityAddTraits(.isAdjustable)
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
