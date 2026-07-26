import XCTest

final class RHVoiceDownloadableVoicesTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("dl-voices-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeVoiceDir(_ id: String, info: String?, meta: RHVoiceDownloadableVoices.DownloadedVoiceMeta? = nil) throws -> URL {
        let dir = tempRoot.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let info {
            try info.write(to: dir.appendingPathComponent("voice.info"), atomically: true, encoding: .utf8)
        }
        if let meta {
            let data = try JSONEncoder().encode(meta)
            try data.write(to: dir.appendingPathComponent(RHVoiceDownloadableVoices.metaFileName))
        }
        return dir
    }

    func testScanReadsMetaJson() throws {
        let meta = RHVoiceDownloadableVoices.DownloadedVoiceMeta(
            id: "bdl",
            engineName: "Bdl",
            displayName: "BDL",
            language: "en-US",
            gender: "male",
            version: 1,
            sampleText: "Hello! This is the BDL voice."
        )
        _ = try makeVoiceDir("bdl", info: "name=Bdl\nlanguage=English\nformat=4\n", meta: meta)

        let voices = RHVoiceDownloadableVoices.scanInstalledVoices(rootOverride: tempRoot)
        XCTAssertEqual(voices.count, 1)
        XCTAssertEqual(voices[0].name, "BDL")
        XCTAssertEqual(voices[0].identifier, "com.rhvoice.UkrainianVoices.bdl")
        XCTAssertEqual(voices[0].language, "en-US")
        XCTAssertEqual(voices[0].profileName, "Bdl")
        XCTAssertEqual(voices[0].sampleText, "Hello! This is the BDL voice.")
    }

    func testScanFallsBackToVoiceInfo() throws {
        _ = try makeVoiceDir("slt", info: "name=Slt\nlanguage=English\nformat=4\n")

        let voices = RHVoiceDownloadableVoices.scanInstalledVoices(rootOverride: tempRoot)
        XCTAssertEqual(voices.count, 1)
        XCTAssertEqual(voices[0].name, "Slt")
        XCTAssertEqual(voices[0].profileName, "Slt")
        XCTAssertEqual(voices[0].language, "en-US")
    }

    func testScanIgnoresDirWithoutVoiceInfo() throws {
        _ = try makeVoiceDir("broken", info: nil)
        _ = try makeVoiceDir("ksp", info: "name=Ksp\nlanguage=English\n")

        let voices = RHVoiceDownloadableVoices.scanInstalledVoices(rootOverride: tempRoot)
        XCTAssertEqual(voices.map(\.profileName), ["Ksp"])
    }

    func testScanIgnoresLooseFiles() throws {
        try "junk".write(to: tempRoot.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)

        let voices = RHVoiceDownloadableVoices.scanInstalledVoices(rootOverride: tempRoot)
        XCTAssertTrue(voices.isEmpty)
    }

    func testScanIsSortedByDirectoryName() throws {
        _ = try makeVoiceDir("slt", info: "name=Slt\nlanguage=English\n")
        _ = try makeVoiceDir("bdl", info: "name=Bdl\nlanguage=English\n")

        let voices = RHVoiceDownloadableVoices.scanInstalledVoices(rootOverride: tempRoot)
        XCTAssertEqual(voices.map(\.profileName), ["Bdl", "Slt"])
    }

    func testEmptyRootReturnsEmpty() {
        let missing = tempRoot.appendingPathComponent("does-not-exist", isDirectory: true)
        XCTAssertTrue(RHVoiceDownloadableVoices.scanInstalledVoices(rootOverride: missing).isEmpty)
    }

    func testVoiceCatalogAlwaysContainsBuiltInVoices() {
        let catalog = RHVoiceSharedSettings.voiceCatalog
        let builtIn = RHVoiceSharedSettings.builtInVoiceCatalog
        XCTAssertGreaterThanOrEqual(catalog.count, builtIn.count)
        for voice in builtIn {
            XCTAssertTrue(catalog.contains(voice), "Вбудований голос \(voice.name) зник з каталогу")
        }
        XCTAssertEqual(Array(catalog.prefix(builtIn.count)), builtIn, "Вбудовані голоси мають іти першими")
    }
}
