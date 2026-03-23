import Foundation

public struct VoiceSettings: Codable {
    public var voiceID: String = ""
    public var voiceProfile: String?
    public var supportsLanguageSwitching = false

    public init(voiceID: String, voiceProfile: String? = nil, supportsLanguageSwitching: Bool = false) {
        self.voiceID = voiceID
        self.voiceProfile = voiceProfile
        self.supportsLanguageSwitching = supportsLanguageSwitching
    }
}

extension VoiceSettings: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(voiceID.hashValue)
        hasher.combine(voiceProfile.hashValue)
        hasher.combine(supportsLanguageSwitching.hashValue)
    }
}
