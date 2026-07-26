# Завантажувані мови та голоси (multilang)

Гілка: `feature/multilang-en`. Стан: v1 — англійська мова, 4 голоси CMU.

## Ідея

Українські голоси лишаються вбудованими в бандл (як завжди). Голоси інших мов
користувач завантажує з інтерфейсу застосунку («Мови» → мова → «Завантажити»).
Мовні дані англійської ВЖЕ в бандлі (2.6 МБ, бо українська оголошена
`bilingual=English`) — докачуються лише голоси.

## Звідки качаємо

GitHub-реліз нашого репозиторію: тег `voice-data-v1`
(https://github.com/abuten1977-design/RHVoiceUkraine/releases/tag/voice-data-v1).

- `manifest.json` — каталог мов/голосів: id, назви, розмір, sha256, URL.
- `voice-en-<id>-v1.zip` — розпакований формат голосу RHVoice
  (voice.info, voice.params, 16000/, 24000/ + ліцензія).

Голоси v1 (усі — ліцензія CMU, вільна для будь-якого використання, App Store OK):
Bdl (чол.), Clb (жін.), Slt (жін.), Ksp (чол., індійський акцент).
Alan/Evgeniy-Eng/Lyubov НЕ включені: Alan — ліцензія не задокументована,
решта — CC BY-NC-ND (некомерційна, для App Store не підходить).

Оновлення каталогу: `gh release upload voice-data-v1 <файл> --clobber`.

## Як зберігається

`<App Group>/DownloadedVoices/voices/<id>/` — розпакований голос + наш
`meta.json` (id, engineName, displayName, bcp47, gender, sampleText).
На iOS з усіх файлів знято FileProtection (читання на заблокованому екрані).

## Як голос підхоплює движок

`RHVoice_init_params.resource_paths` — офіційний механізм ядра RHVoice
(NULL-terminated список папок з voice.info). Обидва мости
(`RHVoiceCore/Bridge/Sources/RHVoiceEngine.mm` і `RHVoiceKit/Sources/RHVoiceEngine.mm`)
сканують папку завантажених голосів на init. Після download/delete застосунок
шле Darwin-нотифікацію `com.rhvoice.UkrainianVoices.downloadedVoicesChanged` —
движки переініціалізуються при наступному синтезі, кеші списків оновлюються.

## Як голос бачить система

`UkrainianSpeechSynthesizer.speechVoices` = 4 вбудовані + динамічний список із
кеша `RHVoiceDownloadedVoicesCache` (без файлового I/O на гарячому шляху —
урок task-082/086 про зависання containerURL на macOS 26). Застосунок після
зміни складу викликає `AVSpeechSynthesisProviderVoice.updateSpeechVoices()`.

## Ключові файли

- `UkrainianVoicesApp/Shared/RHVoiceDownloadableVoices.swift` — сканер + кеш.
- `UkrainianVoicesApp/App/VoiceDownloadManager.swift` — манифест, завантаження
  (URLSession + перевірка sha256 + ZIPFoundation), видалення.
- `UkrainianVoicesApp/App/DownloadableLanguagesView.swift` — UI «Мови».
- `RHVoiceSharedSettings.voiceCatalog` — тепер computed:
  `builtInVoiceCatalog + завантажені`.
- project.yml: пакет ZIPFoundation (лише app-таргети).
- macOS entitlements: додано `com.apple.security.network.client`.

## Що свідомо відкладено

- Завантаження мовних даних (для мов, яких нема в бандлі) — модель манифеста
  вже має поле `languageDataBuiltIn`.
- Прогрес фонової загрузки при згорнутому застосунку (URLSession background).
- Демо-прослуховування голосу ДО завантаження (demoUrl як у поляків).
