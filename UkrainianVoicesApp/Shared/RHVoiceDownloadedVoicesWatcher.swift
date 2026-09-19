import Foundation

/// Вирішує, чи треба народити рушій заново через зміну складу завантажених голосів.
///
/// НАВІЩО ЦЕЙ ФАЙЛ ІСНУЄ. Рушій RHVoice читає `resource_paths` ЛИШЕ на init —
/// API «перечитай теки» у нього немає. Тому про щойно завантажений голос йому
/// треба сказати окремо. Досі єдиним способом була одноразова Darwin-нотифікація
/// `downloadedVoicesChanged`: застосунок її шле, міст слухає. Слабке місце —
/// сигнал не стає в чергу і не доходить до ЗАМОРОЖЕНОГО процесу розширення
/// (розбір 31.08.2026: у Даниїла голос мовчав до ДРУГОГО перезавантаження,
/// в Остапа на іншому телефоні той самий білд запрацював одразу).
/// Тут ця залежність знімається: розширення саме звіряє коротку довідку про
/// склад голосів і більше не покладається на те, що сигнал дійшов.
///
/// ЧОМУ РІШЕННЯ ЖИВЕ У SWIFT, А НЕ В МОСТІ. Міст не покритий жодним тестом
/// (усі 166 — про Swift-шар), і він лежить прямо на шляху мовлення. Тому в
/// мості залишено тільки виконання — `reinitializeEngineForDownloadedVoicesChange`,
/// а вся політика (що вважати зміною, коли мовчати, коли запам'ятовувати) тут,
/// під тестами.
struct RHVoiceDownloadedVoicesWatcher {
    /// Скільки мовчати після спроби. Якщо переініціалізація зривається раз за
    /// разом, рушій НЕ має народжуватись заново на кожній фразі — це чутно одразу.
    static let reinitCooldown: CFAbsoluteTime = 10.0

    /// Довідка, з якою рушій реально працює зараз.
    private(set) var knownSignature: String
    private(set) var lastAttemptAt: CFAbsoluteTime

    init(knownSignature: String = "", lastAttemptAt: CFAbsoluteTime = 0) {
        self.knownSignature = knownSignature
        self.lastAttemptAt = lastAttemptAt
    }

    enum Decision: Equatable {
        /// Нічого не робимо: склад той самий, або читання зірвалось, або ще кулдаун.
        case doNothing
        /// Рушій щойно народився і вже знає цей склад — просто запам'ятати.
        case adopt
        /// Склад змінився — народити рушій заново.
        case reinitialize
    }

    /// Рушій народився (або ми вперше дізнались його стан): прийняти довідку
    /// без переініціалізації — він щойно сам прочитав теки.
    mutating func adopt(signature: String) {
        knownSignature = signature
    }

    mutating func decide(signature: String, now: CFAbsoluteTime) -> Decision {
        // Збій читання НЕ є зміною складу. Інакше помилка виглядала б як
        // «голоси зникли» і народжувала рушій заново на порожньому місці —
        // рівно та хвороба, що з'їдала словник замін до збірки 232.
        guard signature != "unreadable", !signature.isEmpty else { return .doNothing }
        guard signature != knownSignature else { return .doNothing }
        // Стану ще не знаємо (рушія підняли повз наш облік) — приймаємо як є.
        guard !knownSignature.isEmpty else { return .adopt }
        guard now - lastAttemptAt >= Self.reinitCooldown else { return .doNothing }
        return .reinitialize
    }

    /// Викликати ПЕРЕД спробою: фіксує момент, щоб кулдаун діяв і тоді,
    /// коли спроба зірветься.
    mutating func noteAttempt(at now: CFAbsoluteTime) {
        lastAttemptAt = now
    }

    /// Новий склад запам'ятовуємо ЛИШЕ після успіху. Якщо рушій не піднявся,
    /// наступна фраза (після кулдауну) спробує ще раз, а не вважатиме склад
    /// обробленим — урок [[project-dictionary-cache-poisoning]].
    mutating func noteResult(success: Bool, signature: String) {
        guard success else { return }
        knownSignature = signature
    }
}
