import Foundation

public struct IsSynthesizingMessage: MessageHandler, Codable {
    public init() {}
    public func handle(delegate: any MessageHandlerDelegate) -> String { return delegate.isSynthesizingMessage() }
}
