//
//  SettingsStore.swift
//
//
//  Created by Ihor Shevchuk on 20.11.2022.
//
//  Copyright (C) 2022–2024 Ihor Shevchuk
//  Copyright (C) 2025 Non-Routine LLC
//  Contact: contact@nonroutine.com
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import Foundation
import Combine
import RHVoice

public class SettingsStore {

    public var quality: RHSpeechUtteranceQuality {
        get {
            return settings.quality
        }
        set {
            settings.quality = newValue
            setValuesToStore()
        }
    }

    public var automaticUpdates: Bool {
        get {
            return settings.automaticUpdates
        }

        set {
            settings.automaticUpdates = newValue
            setValuesToStore()
        }
    }

    public var languageSwitching: Bool {
        get {
            return settings.languageSwitching
        }

        set {
            settings.languageSwitching = newValue
            setValuesToStore()
        }
    }

    public var voicesSettings: [VoiceSettings] {
        return Array(settings.voicesSettings.values)
    }

    public var configRevision: Int {
        return settings.configRevision
    }

    public static let shared = SettingsStore()

    public var userDefaults: UserDefaults = {
        if let suiteDefaults = UserDefaults(suiteName: GeneratedConstants.applicationGroupIdentifier) {
            return suiteDefaults
        }
        Log.error("Failed to initialize UserDefaults suite for app group \(GeneratedConstants.applicationGroupIdentifier). Falling back to standard UserDefaults.")
        return .standard
    }()

    public var settings = SettingsItems()

    public var settingsUpdatedObservation: AnyCancellable?

    init() {
        updateValuses()
        settingsUpdatedObservation = userDefaults.publisher(for: \.settingsData)
            .sink(receiveValue: { [weak self] _ in
                self?.updateValuses()
            })
    }

    private func setValuesToStore() {
        userDefaults.settings = settings
    }

    public func updateValuses() {
        if userDefaults.settingsData != nil {
            let settings = userDefaults.settings
            self.settings = settings
        } else {
            Log.info("There are no setting stored in user defaults. Using default values")
            self.settings = SettingsItems()
        }
    }

    public func bumpConfigRevision() {
        settings.configRevision = settings.configRevision &+ 1
        setValuesToStore()
    }

    public func languageSettings(for code: String) -> LanguageSettings {
        return settings.languageSettings(for: code)
    }

    public func setLanguageSettings(for code: String, languageSettings: LanguageSettings) {
        settings.setLanguageSettings(for: code, languageSettings: languageSettings)
        setValuesToStore()
    }

    func voiceSettings(for voiceId: String) -> VoiceSettings {
        return settings.voicesSettings(for: voiceId)
    }

    public func setVoiceSettings(for voiceId: String, voiceSettings: VoiceSettings) {
        settings.setVoicesSettings(for: voiceId, voiceSettings: voiceSettings)
        setValuesToStore()
    }

    public func removeVoiceSettings(for voiceId: String) {
        settings.removeVoicesSettings(for: voiceId)
        setValuesToStore()
    }

    @FileBacked(
        default: [],
        urlProvider: { FileManager.default.rhvoiceSupportedVoicesDataFileURL },
        makeUnprotected: true
    )
    public var supportedVoices: [RHSpeechSynthesisProviderVoice]

    @FileBacked(
        default: [],
        urlProvider: { FileManager.default.documentsDirectoryURL
            .appendingPathComponent(Constants.SupportedVoicesDataFile) },
        makeUnprotected: true
    )
    public var supportedVoicesExtension: [RHSpeechSynthesisProviderVoice]
}

fileprivate extension UserDefaults {

    private static let userDefaultsSettingsKey = "RHVoiceSettings"

    @objc dynamic public var settingsData: Data? {
        get {
            synchronize()
            return object(forKey: UserDefaults.userDefaultsSettingsKey) as? Data
        }
        set {
            guard let newValue else {
                removeObject(forKey: UserDefaults.userDefaultsSettingsKey)
                return
            }
            set(newValue, forKey: UserDefaults.userDefaultsSettingsKey)
            synchronize()
        }
    }

    public var settings: SettingsItems {
        get {
            if let settingsData {
                let decoder = JSONDecoder()
                if let settings = try? decoder.decode(SettingsItems.self, from: settingsData) {
                   return settings
                }
            }
            return SettingsItems()
        }

        set {
            let encoder = JSONEncoder()
            if let encoded = try? encoder.encode(newValue) {
                settingsData = encoded
            }
        }
    }
}
