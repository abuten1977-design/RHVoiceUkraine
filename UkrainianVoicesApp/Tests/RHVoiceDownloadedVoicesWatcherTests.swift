import XCTest

/// Тести на механізм, що знімає залежність від одноразової Darwin-нотифікації:
/// розширення саме помічає появу/зникнення завантаженого голосу.
/// Борг, заради якого це написано: «англійський голос мовчить до ДРУГОГО
/// перезавантаження» (docs/DEBTS.md, розбір 31.08.2026).
final class RHVoiceDownloadedVoicesWatcherTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("voices-signature-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func createRoot() throws {
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    @discardableResult
    private func makeVoice(_ id: String, withInfo: Bool = true) throws -> URL {
        let dir = tempRoot.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if withInfo {
            try "name=\(id)\n".write(to: dir.appendingPathComponent("voice.info"), atomically: true, encoding: .utf8)
        }
        return dir
    }

    private func signature() -> String {
        RHVoiceDownloadableVoices.installedVoicesSignature(rootOverride: tempRoot)
    }

    // MARK: - Довідка про склад голосів

    func testMissingFolderIsNotTheSameAsEmptyFolder() throws {
        // Теки ще немає (жодного голосу не завантажували).
        XCTAssertEqual(signature(), "none")

        try createRoot()
        XCTAssertEqual(signature(), "0:")
    }

    func testDownloadedVoiceAppearsInSignature() throws {
        try createRoot()
        try makeVoice("bdl")
        XCTAssertTrue(signature().hasPrefix("1:bdl@"), "довідка: \(signature())")
    }

    func testSignatureIsStableWhenNothingChanges() throws {
        try createRoot()
        try makeVoice("bdl")
        XCTAssertEqual(signature(), signature())
    }

    func testDeletingVoiceChangesSignature() throws {
        try createRoot()
        let dir = try makeVoice("bdl")
        let before = signature()
        try FileManager.default.removeItem(at: dir)
        XCTAssertNotEqual(signature(), before)
        XCTAssertEqual(signature(), "0:")
    }

    func testHalfUnpackedVoiceIsNotCounted() throws {
        // Тека є, voice.info ще немає — голос не встановлений.
        try createRoot()
        try makeVoice("bdl", withInfo: false)
        XCTAssertEqual(signature(), "0:")
    }

    // MARK: - Рішення

    func testSameCompositionDoesNothing() {
        var watcher = RHVoiceDownloadedVoicesWatcher(knownSignature: "1:bdl@100")
        XCTAssertEqual(watcher.decide(signature: "1:bdl@100", now: 1000), .doNothing)
    }

    func testUnreadableFolderIsNotTreatedAsChange() {
        // Головне правило: збій читання НЕ означає «голоси зникли».
        var watcher = RHVoiceDownloadedVoicesWatcher(knownSignature: "1:bdl@100")
        XCTAssertEqual(watcher.decide(signature: "unreadable", now: 1000), .doNothing)
        XCTAssertEqual(watcher.decide(signature: "", now: 1000), .doNothing)
        XCTAssertEqual(watcher.knownSignature, "1:bdl@100")
    }

    func testUnknownStateIsAdoptedWithoutReinit() {
        var watcher = RHVoiceDownloadedVoicesWatcher()
        XCTAssertEqual(watcher.decide(signature: "1:bdl@100", now: 1000), .adopt)
    }

    func testChangedCompositionAsksForReinit() {
        var watcher = RHVoiceDownloadedVoicesWatcher(knownSignature: "0:")
        XCTAssertEqual(watcher.decide(signature: "1:bdl@100", now: 1000), .reinitialize)
    }

    func testCooldownPreventsReinitStorm() {
        var watcher = RHVoiceDownloadedVoicesWatcher(knownSignature: "0:")
        XCTAssertEqual(watcher.decide(signature: "1:bdl@100", now: 1000), .reinitialize)
        watcher.noteAttempt(at: 1000)
        watcher.noteResult(success: false, signature: "1:bdl@100")

        // Одразу після невдалої спроби — мовчимо, інакше рушій народжувався б
        // заново на кожній фразі.
        XCTAssertEqual(watcher.decide(signature: "1:bdl@100", now: 1001), .doNothing)
        // Після кулдауну пробуємо ще раз.
        let later = 1000 + RHVoiceDownloadedVoicesWatcher.reinitCooldown
        XCTAssertEqual(watcher.decide(signature: "1:bdl@100", now: later), .reinitialize)
    }

    func testFailedReinitIsNotRemembered() {
        var watcher = RHVoiceDownloadedVoicesWatcher(knownSignature: "0:")
        watcher.noteResult(success: false, signature: "1:bdl@100")
        XCTAssertEqual(watcher.knownSignature, "0:", "зірвану спробу не можна запам'ятовувати як оброблену")
    }

    func testSuccessfulReinitIsRemembered() {
        var watcher = RHVoiceDownloadedVoicesWatcher(knownSignature: "0:")
        watcher.noteResult(success: true, signature: "1:bdl@100")
        XCTAssertEqual(watcher.knownSignature, "1:bdl@100")
        XCTAssertEqual(watcher.decide(signature: "1:bdl@100", now: 9999), .doNothing)
    }

    // MARK: - Наскрізний сценарій Даниїла

    func testDownloadThenSpeakIsNoticedWithoutAnySignal() throws {
        // Рушій піднявся, коли завантажених голосів ще не було.
        try createRoot()
        var watcher = RHVoiceDownloadedVoicesWatcher()
        watcher.adopt(signature: signature())
        XCTAssertEqual(watcher.knownSignature, "0:")

        // Користувач завантажив англійський голос. Нотифікація не дійшла.
        try makeVoice("bdl")

        // Наступна фраза цим голосом — розширення помічає зміну САМО.
        XCTAssertEqual(watcher.decide(signature: signature(), now: 5000), .reinitialize)
    }
}
