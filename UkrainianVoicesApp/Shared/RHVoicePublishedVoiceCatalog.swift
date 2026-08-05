import Foundation

/// Stable, durable catalog that the app publishes before asking iOS to refresh
/// provider voices. It deliberately contains descriptors, not downloaded-file
/// paths: the extension must never discover a newly downloaded voice while the
/// system is enumerating `speechVoices`.
struct RHVoicePublishedVoiceCatalog: Codable, Equatable {
    static let schemaVersion = 1
    static let fileName = "PublishedVoiceCatalog.json"

    let schema: Int
    let revision: Int
    let descriptors: [RHVoiceVoiceDescriptor]

    var identifiers: [String] { descriptors.map(\.identifier) }

    static func make(downloaded: [RHVoiceVoiceDescriptor], revision: Int = 1) throws -> Self {
        let descriptors = RHVoiceSharedSettings.builtInVoiceCatalog + downloaded
        let identifiers = descriptors.map(\.identifier)
        guard Set(identifiers).count == identifiers.count,
              descriptors.allSatisfy({ !$0.identifier.isEmpty && !$0.language.isEmpty && !$0.profileName.isEmpty }) else {
            throw CatalogError.invalidDescriptors
        }
        return Self(schema: schemaVersion, revision: revision, descriptors: descriptors)
    }

    static func publishedFileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: RHVoiceSharedSettings.appGroupID)?
            .appendingPathComponent(fileName)
    }

    @discardableResult
    static func publishInstalledVoices() throws -> Self {
        guard let url = publishedFileURL() else { throw CatalogError.appGroupUnavailable }
        let oldRevision = load(from: url)?.revision ?? 0
        let catalog = try make(
            downloaded: RHVoiceDownloadableVoices.scanInstalledVoices(),
            revision: oldRevision + 1
        )
        try save(catalog, to: url)
        guard load(from: url) == catalog else { throw CatalogError.readBackMismatch }
        return catalog
    }

    static func loadPublished() -> Self? {
        guard let url = publishedFileURL() else { return nil }
        return load(from: url)
    }

    static func save(_ catalog: Self, to url: URL) throws {
        let data = try JSONEncoder().encode(catalog)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.none], ofItemAtPath: url.path)
        #endif
    }

    static func load(from url: URL) -> Self? {
        guard let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(Self.self, from: data),
              catalog.schema == schemaVersion,
              Set(catalog.identifiers).count == catalog.identifiers.count else { return nil }
        return catalog
    }

    enum CatalogError: LocalizedError {
        case appGroupUnavailable, invalidDescriptors, readBackMismatch
        var errorDescription: String? {
            switch self {
            case .appGroupUnavailable: return "Спільне сховище голосів недоступне."
            case .invalidDescriptors: return "Каталог голосів містить некоректні дані."
            case .readBackMismatch: return "Не вдалося перевірити запис каталогу голосів."
            }
        }
    }
}
