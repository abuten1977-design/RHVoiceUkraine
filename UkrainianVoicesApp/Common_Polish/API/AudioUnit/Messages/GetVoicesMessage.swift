import Foundation

public struct GetVoicesMessage: MessageHandler, Codable {
    public init() {}
    public func handle(delegate: any MessageHandlerDelegate) -> String {
        let voices = delegate.getVoices()
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(voices), let json = String(data: data, encoding: .utf8) {
            return json
        }
        return ""
    }
}
