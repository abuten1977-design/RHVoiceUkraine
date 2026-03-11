//
//  VoiceManager.swift
//  PolishVariant
//
//  Управление голосами и параметрами
//

import Foundation

public class VoiceManager: ObservableObject {
    public static let shared = VoiceManager()
    
    // Ключ для сохранения в UserDefaults
    private let kParametersKey = "RHVoice_Parameters"
    private let kSelectedVoiceKey = "RHVoice_SelectedVoice"
    
    @Published public var parameters: VoiceParameters {
        didSet {
            saveParameters()
        }
    }
    
    @Published public var selectedVoiceIdentifier: String {
        didSet {
            UserDefaults.standard.set(selectedVoiceIdentifier, forKey: kSelectedVoiceKey)
        }
    }
    
    private init() {
        // Загрузка сохраненных параметров
        if let data = UserDefaults.standard.data(forKey: kParametersKey),
           let saved = try? JSONDecoder().decode(VoiceParameters.self, from: data) {
            self.parameters = saved
        } else {
            self.parameters = VoiceParameters()
        }
        
        // Загрузка выбранного голоса
        self.selectedVoiceIdentifier = UserDefaults.standard.string(forKey: kSelectedVoiceKey) ?? "com.rhvoice.ukrainian.anatol"
    }
    
    private func saveParameters() {
        if let data = try? JSONEncoder().encode(parameters) {
            UserDefaults.standard.set(data, forKey: kParametersKey)
        }
    }
    
    // MARK: - Public Methods
    
    public func updateParameter<T>(_ keyPath: WritableKeyPath<VoiceParameters, T>, to value: T) {
        var newParams = parameters
        newParams[keyPath: keyPath] = value
        self.parameters = newParams.validated()
    }
    
    public func resetToDefaults() {
        self.parameters = VoiceParameters()
    }
}
