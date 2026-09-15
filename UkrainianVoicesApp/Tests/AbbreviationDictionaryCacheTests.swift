import XCTest

/// Сторож дефекта, найденного 14.09.2026 по отзыву тестера Даниила
/// (iPhone 12 mini, iOS 26.6.2, сборка 231): после обновления его словари
/// замен переставали действовать и оживали только после того, как он удалял
/// записи и создавал такие же заново.
///
/// Причина: одна неудачная попытка чтения файла превращалась в ПУСТОЙ словарь,
/// и при этом подпись файла запоминалась как обработанная. Дальше кэш считал,
/// что этот файл он уже прочитал, и к нему не возвращался — пользовательские
/// замены пропадали до тех пор, пока файл не перезапишут руками.
final class AbbreviationDictionaryCacheTests: XCTestCase {

    private let signatureA = AbbreviationDictionaryFileSignature(
        exists: true, modificationDate: Date(timeIntervalSince1970: 1_000), size: 42)
    private let signatureB = AbbreviationDictionaryFileSignature(
        exists: true, modificationDate: Date(timeIntervalSince1970: 2_000), size: 77)

    private let userEntry = AbbreviationDictionaryEntry(
        abbreviation: "смт", replacement: "селище міського типу")

    func testSuccessfulReadIsAppliedAndSignatureRemembered() {
        let cache = AbbreviationDictionaryCache()
        let decision = cache.apply(loadResult: .success([userEntry]), signature: signatureA, source: "test")

        guard case .applied = decision else {
            return XCTFail("успешное чтение должно применяться, получено: \(decision)")
        }
        XCTAssertTrue(cache.cachedEntriesForTesting.contains(userEntry))
        XCTAssertEqual(cache.cachedSignatureForTesting, signatureA)
    }

    func testReadFailureKeepsPreviousEntries() {
        let cache = AbbreviationDictionaryCache()
        cache.apply(loadResult: .success([userEntry]), signature: signatureA, source: "test")

        let decision = cache.apply(loadResult: .failure(.unreadableFile), signature: signatureB, source: "test")

        XCTAssertEqual(decision, .keptPreviousAfterReadFailure)
        XCTAssertTrue(
            cache.cachedEntriesForTesting.contains(userEntry),
            "ошибка чтения не должна стирать уже известные пользовательские замены"
        )
    }

    func testReadFailureDoesNotRememberSignature() {
        // Самое главное: если запомнить подпись после неудачи, кэш решит, что
        // файл уже прочитан, и пользовательские замены не вернутся НИКОГДА.
        let cache = AbbreviationDictionaryCache()
        cache.apply(loadResult: .success([userEntry]), signature: signatureA, source: "test")

        cache.apply(loadResult: .failure(.unreadableFile), signature: signatureB, source: "test")

        XCTAssertEqual(
            cache.cachedSignatureForTesting, signatureA,
            "после ошибки чтения подпись обязана остаться прежней, иначе повторной попытки не будет"
        )
    }

    func testMissingFileIsNotTreatedAsReadFailure() {
        // «Файла нет» — законный случай: пользовательских замен просто нет.
        // Он должен применяться как успех, оставляя встроенные замены.
        let cache = AbbreviationDictionaryCache()
        let empty = AbbreviationDictionaryFileSignature(exists: false, modificationDate: nil, size: 0)

        let decision = cache.apply(loadResult: .success([]), signature: empty, source: "test")

        guard case .applied = decision else {
            return XCTFail("отсутствие файла — не ошибка чтения, получено: \(decision)")
        }
        XCTAssertEqual(cache.cachedSignatureForTesting, empty)
        XCTAssertFalse(cache.cachedEntriesForTesting.isEmpty, "встроенные замены должны остаться")
    }

    func testRecoveryAfterFailureWhenFileBecomesReadableAgain() {
        let cache = AbbreviationDictionaryCache()
        cache.apply(loadResult: .success([userEntry]), signature: signatureA, source: "test")
        cache.apply(loadResult: .failure(.unreadableFile), signature: signatureB, source: "test")

        let recovered = AbbreviationDictionaryEntry(abbreviation: "обл.", replacement: "область")
        let decision = cache.apply(loadResult: .success([recovered]), signature: signatureB, source: "test")

        guard case .applied = decision else {
            return XCTFail("после восстановления чтения записи должны примениться")
        }
        XCTAssertTrue(cache.cachedEntriesForTesting.contains(recovered))
        XCTAssertEqual(cache.cachedSignatureForTesting, signatureB)
    }

    // MARK: - Повторная попытка после сбоя (ветка, найденная критиком)

    /// Ждёт, пока кэш сделает ожидаемое число походов за файлом.
    private func waitForReads(_ cache: AbbreviationDictionaryCache, expected: Int, timeout: TimeInterval = 2) {
        let deadline = Date().addingTimeInterval(timeout)
        while cache.readAttemptCount < expected && Date() < deadline {
            usleep(10_000)
        }
    }

    func testNoFileReadsWhenNothingChangedAndNoFailure() {
        // Путь речи: подпись та же, сбоев не было — файл читать НЕЛЬЗЯ.
        // Лишний ввод-вывод здесь уже подвешивал голос (урок task-082/086).
        let signature = signatureA
        let cache = AbbreviationDictionaryCache(
            loadEntries: { .success([self.userEntry]) },
            readSignature: { signature },
            now: { Date() }
        )
        cache.apply(loadResult: .success([userEntry]), signature: signature, source: "seed")
        let readsAfterSeed = cache.readAttemptCount

        for _ in 0..<50 { cache.reloadIfFileChanged() }

        XCTAssertEqual(cache.readAttemptCount, readsAfterSeed, "при неизменной подписи кэш не должен ходить за файлом")
    }

    func testFailureDoesNotCauseReadOnEverySegment() {
        // Блокер, найденный критиком: после сбоя подпись намеренно не
        // запоминается, поэтому «изменилась» истинно всегда — без кулдауна
        // чтение случалось бы на каждый кусок фразы.
        var clock = Date(timeIntervalSince1970: 10_000)
        let cache = AbbreviationDictionaryCache(
            loadEntries: { .failure(.unreadableFile) },
            readSignature: { self.signatureA },
            now: { clock }
        )
        cache.apply(loadResult: .failure(.unreadableFile), signature: signatureA, source: "seed")
        let readsAfterSeed = cache.readAttemptCount

        // 120 кусков речи за те же полсекунды по часам
        for _ in 0..<120 { cache.reloadIfFileChanged() }
        clock = clock.addingTimeInterval(0.5)
        for _ in 0..<120 { cache.reloadIfFileChanged() }

        XCTAssertEqual(cache.readAttemptCount, readsAfterSeed, "внутри кулдауна повторных чтений быть не должно")
    }

    func testFailureIsRetriedAfterCooldown() {
        var clock = Date(timeIntervalSince1970: 10_000)
        var result: Result<[AbbreviationDictionaryEntry], AbbreviationDictionaryError> = .failure(.unreadableFile)
        let cache = AbbreviationDictionaryCache(
            loadEntries: { result },
            readSignature: { self.signatureA },
            now: { clock }
        )
        cache.apply(loadResult: .failure(.unreadableFile), signature: signatureA, source: "seed")
        let readsAfterSeed = cache.readAttemptCount

        clock = clock.addingTimeInterval(3)      // кулдаун прошёл
        result = .success([userEntry])           // файл снова читается
        cache.reloadIfFileChanged()
        waitForReads(cache, expected: readsAfterSeed + 1)

        XCTAssertEqual(cache.readAttemptCount, readsAfterSeed + 1, "после кулдауна должна быть ровно одна новая попытка")
        XCTAssertTrue(cache.cachedEntriesForTesting.contains(userEntry), "восстановленный словарь должен примениться")
        XCTAssertEqual(cache.cachedSignatureForTesting, signatureA)
    }
}
