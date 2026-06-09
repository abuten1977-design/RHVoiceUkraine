# RHVoice Ukraine — Состояние проекта (2026-05-09)

## Что это

Украинский синтезатор речи для VoiceOver на macOS и iOS. Использует движок RHVoice (C++).

## Как устроено

Приложение (app) — экран настроек, выбор голосов, ползунки скорости/тона.
Extension (плагин) — невидимая часть, iOS/macOS вызывает когда VoiceOver хочет говорить.
Движок (RHVoice C++) — превращает текст в звук.

Связь: VoiceOver просит extension озвучить текст, extension вызывает движок, получает звук, отдаёт VoiceOver.

## Текущее состояние

macOS: РАБОТАЕТ. Синхронный синтез, скорость/тон/громкость применяются, все голоса доступны.

iOS: НЕ РАБОТАЕТ полностью. Голоса появляются в VoiceOver (после перезагрузки iPhone), но МОЛЧАТ при навигации. В превью внутри приложения — говорят.

## Что сделано (хронология)

1. Синхронный синтез (macOS) — убрали ring buffer, сделали как eSpeak
2. Скорость — логарифмическая кривая, dont_clip_rate всегда
3. Параметры — pitch/volume/rate из настроек передаются в движок
4. Тег iOS — исправлен на "Speech Synthesizer" (как у eSpeak/Piper)
5. SPM рефакторинг — C++ компилируется из исходников (не .a файлы)
6. iOS синхронный синтез — убрали стриминг, сделали как macOS
7. Все 4 голоса всегда видны (без фильтрации)
8. Множество TestFlight билдов загружено

## Главная нерешённая проблема

На iPhone голоса МОЛЧАТ при навигации VoiceOver. Появляются в списке но не говорят. В превью внутри приложения — работают.

Возможные причины (не проверены):
- Extension крашится при вызове от VoiceOver
- Синтез слишком медленный и VoiceOver не дожидается
- App Group не работает и extension не может инициализировать движок
- Какая-то разница между тем как VoiceOver вызывает extension и как app вызывает preview

## Доки с исследованиями

docs/analysis-espeak-ios.md — полный анализ eSpeak iOS (как работает, регистрация, аудио)
docs/analysis-piper-ios.md — полный анализ Piper iOS
docs/analysis-rhvoice-ios.md — анализ нашего iOS extension
docs/espeak-vs-rhvoice-changes.md — сравнение eSpeak vs наш код, список отличий
docs/code-structure-map.md — карта всех файлов проекта и связей
docs/ios-audit-roadmap.md — дорожная карта iOS фиксов
docs/macos-audit-results.md — аудит macOS версии
docs/spm-refactoring-plan.md — план перехода на SPM
docs/streaming-implementation-plan.md — план стриминга (отменён, вернулись к синхронному)

## Ключевые файлы

UkrainianVoicesApp/Extension/Provider/UkrainianSpeechSynthesizer.swift — главный файл extension
UkrainianVoicesApp/Extension/Info-iOS.plist — регистрация extension в iOS
UkrainianVoicesApp/Shared/RHVoiceSharedSettings.swift — настройки
UkrainianVoicesApp/project.yml — конфигурация проекта (XcodeGen)
RHVoiceCore/Package.swift — SPM пакет с C++ движком

## Сборка

macOS: bash ~/Desktop/rebuild.sh
iOS: git push + GitHub Actions workflow "iOS Unsigned Manual Build" + скачать + xcodebuild -exportArchive с upload в TestFlight

## Репозиторий

git@github.com:abuten1977-design/RHVoiceUkraine.git
Ветка: ci/macos-gates-2026-04-26
