# docs/archive — застарілі документи

Сюди перенесені документи, що описують **старі/відкинуті** підходи і суперечать поточному стану проєкту (audit 2026-06-09, гілка cleanup-audit-2026-06). Зберігаються для **історії** (Phase 2 HISTORY_THROUGHLINE), НЕ є актуальною документацією.

- `README.md` — стара cmake-збірка (зараз xcodegen).
- `ROADMAP_CLEAN_FRAMEWORK.md`, `RHVOICEKIT_XCFRAMEWORK.md` — план XCFramework, не реалізований (обрано компіляцію з вихідника).
- `streaming-implementation-plan.md` — стрімінг відкинуто (sync-but-async pipeline).
- `ios-spm-build-analysis.md`, `spm-refactoring-plan.md` — перехід на SwiftPM завершено.
- `project-status-0509.md` — застарілий знімок статусу.
- `ios-audit-roadmap.md`, `ios-silence-analysis.md` — травневе розслідування «тиші», перекрите.

Актуальна документація: `RHVoiceNewDocs/`, `README_SYNTHESIZER.md`, `docs/MACOS_*`, `PRE_BUILD_CHECKLIST.md`.

## Додано 2026-06-09 (друга партія — застарілий зміст):
- `code-structure-map.md` — карта файлів зі згадками `.a` (зараз SwiftPM) + видалені файли. Заміна — Phase 1 `STATE_OF_TRUTH`.
- `analysis-rhvoice-ios.md` — старий стрімінг-дизайн (`onChunk`), якого вже немає.
- `macos-audit-results.md` — застарілий результат аудиту macOS.
