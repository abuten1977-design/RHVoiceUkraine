# RHVoice Ukrainian — Архитектура проекта

Дата: 25 марта 2026
Автор: Andriy Butenko
Статус: Рабочий документ

---

## КАК ЭТО РАБОТАЕТ — ПРОСТОЕ ОБЪЯСНЕНИЕ

Представь три слоя:

```
[VoiceOver / iOS / macOS]   ← система Apple
        ↕ AVSpeechSynthesisProviderAudioUnit API
[Speech Extension (.appex)] ← наш Swift код
        ↕ import RHVoice (Swift Package)
[RHVoice C++ движок]        ← C++ библиотека + голоса
```

Когда VoiceOver читает текст:
1. Система отправляет текст в наш Extension
2. Extension передаёт текст в RHVoice движок
3. Движок генерирует аудио (PCM 24000 Hz Float32)
4. Extension отдаёт аудио системе порциями
5. VoiceOver воспроизводит

---

## ЧТО У НАС ЕСТЬ

### 1. RHVoice C++ движок (ГОТОВ)
Путь: ~/Projects/RHVoiceUkraine/RHVoice/
Статус: СОБРАН для всех платформ

Собранные библиотеки:
- macOS x86_64: build_macos_x86_64/ (.dylib)
- iOS ARM64 device: libs_arm64_device/ (.a)
- iOS ARM64 iPhone: libs_arm64_iphone/ (.a)

Голоса (в Extension/Resources/Voices/):
- anatol    — мужской украинский
- marianna  — женский украинский
- natalia   — женский украинский
- volodymyr — мужской украинский
- victoria  — женский английский
- alan      — мужской английский

### 2. RHVoice Swift Package (ГОТОВ — от поляков)
Путь: ~/Projects/rhvoice-ee/Core/
Symlink: ~/Projects/RHVoiceUkraine/UkrainianVoicesApp/Core -> rhvoice-ee/Core

Что это: Swift Package который компилирует C++ движок и
экспортирует модуль RHVoice для использования в Swift коде.
Используется через: import RHVoice

### 3. Common_Polish — общие компоненты (ГОТОВ)
Путь: UkrainianVoicesApp/Common_Polish/
Скопировано из польского проекта.

Ключевые файлы:
- Settings/SettingsStore.swift    — хранение настроек голосов
- Settings/LanguageSettings.swift — скорость, пауза, громкость
- API/RHVoiceApiBridge.swift      — Swift обёртка над C++ API
- Utils/RHSpeechUtterance.swift   — параметры синтеза

### 4. Extension — Speech Synthesis Provider (НУЖНО ДОДЕЛАТЬ)
Путь: UkrainianVoicesApp/Extension/
Ключевой файл: Extension/Provider/UkrainianSpeechSynthesizer.swift

Статус: Структура есть, но синтез — заглушка.
Нужно: Заменить на рабочий код по образцу поляков.

---

## ЧТО НУЖНО СДЕЛАТЬ

### Проблема
UkrainianSpeechSynthesizer.swift не имеет:
- internalRenderBlock (без него нет звука)
- Реального вызова RHVoice движка
- Правильного сигнала завершения синтеза

### Решение
Взять логику из RHVoiceExtensionAudioUnit.swift поляков
(~/Projects/rhvoice-ee/RHVoiceExtension/AudioUnit/)
и адаптировать под наш проект.

Что меняем:
- Имя класса: RHVoiceExtensionAudioUnit → UkrainianSpeechSynthesizer
- Bundle ID: com.rhvoice.* → com.rhvoice.UkrainianVoices.*
- Голоса: польские → украинские (anatol, marianna, natalia, volodymyr)

Что НЕ меняем:
- Логику internalRenderBlock / performRender
- Логику sentencePauseAdded (наше исправление бага)
- Логику silenceGate
- Формат аудио (24000 Hz Float32 моно)

---

## ПОЧЕМУ НЕ НУЖНО ПЕРЕСОБИРАТЬ C++ ДВИЖОК

Движок уже собран. Нам нужен только Swift Package (Core/)
который компилирует его один раз при первой сборке проекта.

Для macOS x86_64 (наш Мак):
- swift build компилирует Core автоматически
- Занимает 30-60 мин первый раз, потом кешируется

Альтернатива (быстрее):
Использовать готовые .dylib из Extension/Libraries/
через linkerSettings в Package.swift — тогда C++ не нужно пересобирать.

---

## АРХИТЕКТУРА SWIFT PACKAGE

```
UkrainianVoicesApp/
├── Package.swift           ← конфигурация
├── Core -> rhvoice-ee/Core ← symlink на C++ движок
├── Common_Polish/          ← общие компоненты (target: Common)
│   ├── Settings/           ← SettingsStore, LanguageSettings
│   ├── API/                ← RHVoiceApiBridge
│   └── Utils/              ← RHSpeechUtterance и др.
└── Extension/              ← Speech Extension (target: Extension)
    ├── Provider/
    │   └── UkrainianSpeechSynthesizer.swift  ← ГЛАВНЫЙ ФАЙЛ
    ├── AudioUnitFactory.swift
    ├── Resources/Voices/   ← данные голосов
    └── Libraries/          ← готовые .dylib (запасной вариант)
```

Зависимости:
- Extension зависит от Common
- Common зависит от RHVoice (из Core)
- Extension зависит от RHVoice (из Core)

---

## СЛЕДУЮЩИЕ ШАГИ

1. Заменить UkrainianSpeechSynthesizer.swift на рабочий код
2. Проверить синтаксис: swiftc -typecheck
3. Собрать: swift build --target Extension
4. Собрать macOS .app через Xcode
5. Проверить что голоса появляются в VoiceOver
6. Коммит в ветку feature/speech-extension-integration

---

## ТЕХНИЧЕСКИЕ ДЕТАЛИ

### Формат аудио
- Sample Rate: 24000 Hz
- Format: Float32 (pcmFormatFloat32)
- Channels: 1 (моно)
- Interleaved: true

### Bundle IDs
- App: com.rhvoice.UkrainianVoices.mac
- Extension: com.rhvoice.UkrainianVoices.Extension.mac
- App Group: group.rhvoice.UkrainianVoices.shared

### Apple Developer
- Team ID: 5NNZPP8CRR
- Team Name: ANDRIY BUTENKO

### Лицензия
GPL-3.0 (совместима с App Store)
Авторы: Ihor Shevchuk, Non-Routine LLC, Andriy Butenko
