import Foundation

public struct SetVoicesMessage: MessageHandler, Codable {
    public let voices: [RHSpeechSynthesisProviderVoice]?
    public init(voices: [RHSpeechSynthesisProviderVoice]?) { self.voices = voices }
    public func handle(delegate: any MessageHandlerDelegate) -> String {
        delegate.set(voices: voices)
        return ""
    }
}
