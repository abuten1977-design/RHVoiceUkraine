# macOS VoiceOver build: подпись через GitHub Actions (что нужно)

Эта инструкция относится к workflow:
- `.github/workflows/build-mac-signed.yml`

## Зачем это нужно

Для текущей macOS линии мы больше **не используем** entitlement
`com.apple.developer.speech-synthesis-provider`.

Рабочая гипотеза после проверки Apple docs и логов: этот entitlement был лишним и сам превращал extension в restricted-код.

Поэтому сейчас цель проще:
- обычная подпись app/appex
- sandbox + app group
- без дополнительного provisioning profile ради speech provider

## Что требуется подготовить (один раз)

### 1) Certificate (.p12)

Экспортируй из Keychain Access сертификат, которым будешь подписывать (обычно `Apple Development`), в `.p12` + пароль.

Секреты GitHub:
- `MACOS_CODESIGN_P12_BASE64` — base64 от файла `.p12`
- `MACOS_CODESIGN_P12_PASSWORD` — пароль от `.p12`

### 2) Signing identity

Нужны только:
- `MACOS_TEAM_ID` — Team ID
- `MACOS_CODE_SIGN_IDENTITY` — строка identity, например `Apple Development: Andriy Butenko (ABCDE12345)`

## Как запустить

1) Залей секреты в репозиторий GitHub (Settings → Secrets and variables → Actions).
2) Запусти workflow `Build RHVoice Mac (Signed)` вручную.
3) Скачай artifact `macos-signed-build` и установи на Mac.

## Что проверить на Mac после установки

1) Логи больше не должны содержать:
- `Disallowing … no eligible provisioning profiles found`
- `Restricted entitlements not validated`

2) После нажатия “Apply enabled voices to system” должны появиться голоса в VoiceOver.
