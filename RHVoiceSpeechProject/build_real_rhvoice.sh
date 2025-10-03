#!/bin/bash

echo "🚀 Сборка RealRHVoiceApp с настоящим RHVoice..."

APP_NAME="RealRHVoiceApp_v2"
BUNDLE_ID="com.test.RealRHVoiceApp"

# Clean previous build
rm -rf .app

# Create app bundle
mkdir -p .app

# Create Info.plist
cat > .app/Info.plist << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>Ukrainian Voice Real</string>
    <key>CFBundleExecutable</key>
    <string></string>
    <key>CFBundleIdentifier</key>
    <string></string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Ukrainian Voice Real</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSRequiresIPhoneOS</key>
    <true/>
    <key>UIDeviceFamily</key>
    <array>
        <integer>1</integer>
        <integer>2</integer>
    </array>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
    </array>
</dict>
</plist>
PLIST_EOF

echo "📝 Info.plist создан"

# Copy RHVoice resources
echo "📁 Копирование ресурсов RHVoice..."
mkdir -p .app/Resources
cp -r RHVoiceModels .app/Resources/
echo "✅ Модели голосов скопированы"

# Compile with RHVoice integration
echo "🔨 Компиляция с RHVoice..."

xcrun -sdk iphonesimulator clang++ -x objective-c++ -fobjc-arc \
    -framework UIKit -framework Foundation \
    -target x86_64-apple-ios17.0-simulator \
    -I./RHVoiceEngine/include \
    -I./RHVoiceEngine/include/core \
    -L./RHVoiceEngine/src \
    -lRHVoice \
    -std=c++17 \
    -Wno-deprecated-declarations \
    RealRHVoiceApp_v2.m \
    RHVoiceEngine/src/RHVoiceWrapper.mm \
    -o .app/

if [ 0 -eq 0 ]; then
    echo "✅ Компиляция успешна!"
    
    # Install and launch
    echo "📱 Установка в симулятор..."
    DEVICE_ID="C842FC02-9AFC-47E1-BD51-DCDBEB5F9476"
    
    xcrun simctl install  .app
    if [ 0 -eq 0 ]; then
        echo "✅ Установка успешна!"
        echo "🚀 Запуск приложения..."
        xcrun simctl launch  
        echo "🎉 Приложение запущено! Проверьте симулятор."
    else
        echo "❌ Ошибка установки"
    fi
else
    echo "❌ Ошибка компиляции"
fi
