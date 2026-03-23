#!/bin/bash
export PATH='/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin'
cd "$(dirname "$0")"

echo "🚀 Шаг 1: Генерация проекта..."
xcodegen generate --spec project_macos_only.yml

echo "🔨 Шаг 2: Сборка macOS приложения..."
xcodebuild -project UkrainianVoicesMac.xcodeproj \
           -scheme UkrainianVoicesMac \
           -configuration Release \
           -arch x86_64 \
           -sdk macosx \
           build -derivedDataPath ./build

if [ $? -eq 0 ]; then
    echo "✅ Сборка успешна!"
    APP_PATH="./build/Build/Products/Release/UkrainianVoicesMac.app"
    echo "📦 Установка в /Applications..."
    rm -rf /Applications/UkrainianVoicesMac.app
    cp -r "$APP_PATH" /Applications/
    xattr -cr /Applications/UkrainianVoicesMac.app
    echo "🎉 Готово! Приложение обновлено в /Applications"
else
    echo "❌ Ошибка сборки"
    exit 1
fi
