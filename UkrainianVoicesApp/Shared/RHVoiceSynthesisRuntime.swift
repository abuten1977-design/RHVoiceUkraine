import Foundation

struct RHVoiceSynthesisRequest: Equatable {
    let text: String
    let voiceIdentifier: String
    let voiceProfileName: String
    let settings: RHVoiceSpeechSettings
    let source: Source

    enum Source: String, Equatable {
        case preview
        case system
    }
}

struct RHVoiceSessionToken: Equatable {
    let id: UUID
    let revision: Int

    static func initial() -> RHVoiceSessionToken {
        RHVoiceSessionToken(id: UUID(), revision: 1)
    }

    func advanced() -> RHVoiceSessionToken {
        RHVoiceSessionToken(id: UUID(), revision: revision + 1)
    }
}

enum RHVoiceSynthesisState: Equatable {
    case idle
    case running(RHVoiceSessionToken)
    case cancelling(RHVoiceSessionToken)
    case completed(RHVoiceSessionToken)
    case cancelled(RHVoiceSessionToken)
    case failed(RHVoiceSessionToken, String)

    var activeToken: RHVoiceSessionToken? {
        switch self {
        case .running(let token),
             .cancelling(let token):
            return token
        case .idle,
             .completed,
             .cancelled,
             .failed:
            return nil
        }
    }
}

final class RHVoiceRuntimeCoordinator {
    private let lock = NSLock()
    private var storedState: RHVoiceSynthesisState = .idle
    private var currentToken = RHVoiceSessionToken.initial()

    var state: RHVoiceSynthesisState {
        lock.lock()
        defer { lock.unlock() }
        return storedState
    }

    func begin(_ request: RHVoiceSynthesisRequest) -> RHVoiceSessionToken {
        _ = request
        lock.lock()
        defer { lock.unlock() }
        currentToken = currentToken.advanced()
        storedState = .running(currentToken)
        return currentToken
    }

    func beginCancel() -> RHVoiceSessionToken? {
        lock.lock()
        defer { lock.unlock() }
        guard let token = storedState.activeToken else {
            return nil
        }
        storedState = .cancelling(token)
        return token
    }

    func markCompleted(_ token: RHVoiceSessionToken) {
        lock.lock()
        defer { lock.unlock() }
        guard token == currentToken else {
            return
        }
        storedState = .completed(token)
    }

    func markCancelled(_ token: RHVoiceSessionToken) {
        lock.lock()
        defer { lock.unlock() }
        guard token == currentToken else {
            return
        }
        storedState = .cancelled(token)
    }

    func markFailed(_ token: RHVoiceSessionToken, message: String) {
        lock.lock()
        defer { lock.unlock() }
        guard token == currentToken else {
            return
        }
        storedState = .failed(token, message)
    }

    func isCurrent(_ token: RHVoiceSessionToken) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return token == currentToken
    }
}

enum RHVoiceSynthesisRequestFactory {
    static func systemRequest(
        text: String,
        voiceIdentifier: String,
        snapshot: RHVoiceSharedSettingsSnapshot
    ) -> RHVoiceSynthesisRequest {
        let descriptor = snapshot.voiceCatalog.first { $0.identifier == voiceIdentifier }
        return RHVoiceSynthesisRequest(
            text: text,
            voiceIdentifier: voiceIdentifier,
            voiceProfileName: descriptor?.profileName ?? voiceIdentifier.components(separatedBy: ".").last ?? RHVoiceSharedSettings.defaultVoiceIdentifier,
            settings: snapshot.effectiveSettings(for: voiceIdentifier),
            source: .system
        )
    }

    static func previewRequest(
        text: String,
        voice: RHVoiceVoiceDescriptor,
        settings: RHVoiceSpeechSettings
    ) -> RHVoiceSynthesisRequest {
        RHVoiceSynthesisRequest(
            text: text,
            voiceIdentifier: voice.identifier,
            voiceProfileName: voice.profileName,
            settings: settings,
            source: .preview
        )
    }
}
