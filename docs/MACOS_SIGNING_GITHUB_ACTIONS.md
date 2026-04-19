# macOS VoiceOver build: подпись через GitHub Actions (что нужно)

Эта инструкция относится к workflow:
- `.github/workflows/build-mac-signed.yml`

## Зачем это нужно

На macOS 13.7.8 extension с entitlement
`com.apple.developer.speech-synthesis-provider`
считается **restricted** и без подходящего provisioning profile система его не запускает (в логах будет `no eligible provisioning profiles found`).

Поэтому нам нужен **реально подписанный** `.appex` с **встроенным provisioning profile**.

## Что требуется подготовить (один раз)

### 1) Certificate (.p12)

Экспортируй из Keychain Access сертификат, которым будешь подписывать (обычно `Apple Development`), в `.p12` + пароль.

Секреты GitHub:
- `MACOS_CODESIGN_P12_BASE64` — base64 от файла `.p12`
- `MACOS_CODESIGN_P12_PASSWORD` — пароль от `.p12`

### 2) Provisioning profiles (2 штуки)

Нужны `.mobileprovision`:
- для app: `com.rhvoice.UkrainianVoices.mac`
- для extension: `com.rhvoice.UkrainianVoices.mac.Extension`

Важно: профили должны быть для той же Team и должны разрешать entitlement(ы) extension, включая `com.apple.developer.speech-synthesis-provider`.

Секреты GitHub:
- `MACOS_APP_PROFILE_BASE64` — base64 `.mobileprovision` для app
- `MACOS_EXT_PROFILE_BASE64` — base64 `.mobileprovision` для extension
- `MACOS_TEAM_ID` — Team ID
- `MACOS_CODE_SIGN_IDENTITY` — строка identity, например `Apple Development: Andriy Butenko (ABCDE12345)`

## Как запустить

1) Залей секреты в репозиторий GitHub (Settings → Secrets and variables → Actions).
2) Запусти workflow `Build RHVoice Mac (Signed)` вручную.
3) Скачай artifact `macos-signed-build` и установи на Mac.

## Что проверить на Mac после установки

1) Внутри extension должен появиться provisioning profile:
- `…/UkrainianVoicesMac.app/Contents/PlugIns/UkrainianVoicesExtensionMac.appex/Contents/embedded.provisionprofile`

2) Логи больше не должны содержать:
- `Disallowing … no eligible provisioning profiles found`
- `Restricted entitlements not validated`

3) После нажатия “Apply enabled voices to system” должны появиться голоса в VoiceOver.

