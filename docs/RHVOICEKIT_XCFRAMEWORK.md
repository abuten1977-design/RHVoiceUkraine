# RHVoiceKit.xcframework (iOS device + macOS) — зачем и как использовать

## Зачем

Мы хотим, чтобы **один и тот же движок** (Objective‑C++ bridge + буферизация + cancel‑логика) использовался:
- в iOS app
- в iOS VoiceOver extension
- в macOS app
- в macOS VoiceOver extension

Для этого удобно собирать `RHVoiceKit` как `XCFramework`, чтобы не размножать разные копии `RHVoiceEngine` по проекту.

Важно: это **не решает** macOS‑проблему с restricted entitlement `com.apple.developer.speech-synthesis-provider` — это отдельная тема подписи/профилей. Но это стабилизирует код движка.

## Что внутри

Артефакт `RHVoiceKit.xcframework.zip` содержит сборки:
- iOS **device** (iphoneos)
- macOS (x86_64)

Симулятор не включён специально (по текущему запросу).

## Где собирается

GitHub Actions workflow:
- `.github/workflows/build-rhvoicekit-xcframework.yml`

Artifact name:
- `rhvoicekit-xcframework`

