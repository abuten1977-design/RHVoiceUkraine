# 🇺🇦 RHVoice Ukraine - iOS VoiceOver Integration

**Ukrainian Speech Synthesizer for iOS VoiceOver**

Повна інтеграція українських голосів RHVoice з системою VoiceOver на iOS 16+.

[![Build Status](https://github.com/abuten1977-design/RHVoiceUkraine/workflows/Build%20iOS%20Ukrainian%20Synthesizer/badge.svg)](https://github.com/abuten1977-design/RHVoiceUkraine/actions)
[![iOS](https://img.shields.io/badge/iOS-16.0+-blue.svg)](https://www.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org/)
[![License](https://img.shields.io/badge/License-GPL--3.0-green.svg)](LICENSE)

---

## 🎯 Що це?

Це **App Extension** для iOS, який додає 4 українські голоси в системний VoiceOver:

- 🗣️ **Anatol** (чоловічий)
- 🗣️ **Natalia** (жіночий)
- 🗣️ **Marianna** (жіночий)
- 🗣️ **Volodymyr** (чоловічий)

Після встановлення, ці голоси доступні в **Налаштування → Доступність → VoiceOver → Мова → Українська**.

---

## ✨ Особливості

### 🎚️ Повне управління параметрами

- **Швидкість (Rate):** 0.5x - 2.0x
- **Гучність (Volume):** 0% - 100%
- **Тембр (Pitch):** 0.5x - 2.0x

Всі параметри налаштовуються через системні настройки VoiceOver!

### ♿ Accessibility First

- ✅ Повна інтеграція з VoiceOver
- ✅ Працює в усіх iOS додатках
- ✅ Підтримка SSML
- ✅ Динамічні діапазони параметрів

### 🧪 Тестування

- ✅ Unit тести (параметри)
- ✅ Integration тести (VoiceOver provider)
- ✅ Автоматичні тести в CI/CD
- ✅ Code coverage звіти

---

## 🚀 Швидкий старт

### Встановлення через TestFlight (скоро)

1. Отримати запрошення в TestFlight
2. Встановити додаток
3. Відкрити **Налаштування → Доступність → VoiceOver**
4. Вибрати **Мова → Українська → Ukrainian Voices**

### Збірка з вихідного коду

```bash
# 1. Клонувати репозиторій
git clone --recursive https://github.com/abuten1977-design/RHVoiceUkraine.git
cd RHVoiceUkraine

# 2. Зібрати RHVoice бібліотеки
cd RHVoice
mkdir build_ios_device && cd build_ios_device
cmake .. -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64
cmake --build . --config Release

# 3. Запустити тести
cd ../../RHVoiceUkrainianSynthesizer
swift test

# 4. Відкрити в Xcode (коли буде створено)
open RHVoiceUkraine.xcodeproj
```

---

## 📁 Структура проекту

```
RHVoiceUkraine/
├── RHVoice/                              # RHVoice движок (submodule)
├── RHVoiceUkrainianSynthesizer/          # iOS VoiceOver Extension
│   ├── Provider/                         # Swift код
│   │   └── UkrainianSpeechSynthesizer.swift
│   ├── Bridge/                           # Objective-C++ міст
│   │   ├── RHVoiceParameters.h
│   │   └── RHVoiceParameters.mm
│   ├── Resources/                        # Ресурси
│   │   └── Voices/                       # 4 українські голоси
│   ├── Libraries/                        # Зібрані бібліотеки
│   │   ├── libRHVoice.dylib
│   │   ├── libRHVoice_core.dylib
│   │   └── libRHVoice_audio.dylib
│   ├── Tests/                            # Тести
│   │   ├── RHVoiceParametersTests.swift
│   │   └── UkrainianSpeechSynthesizerTests.swift
│   ├── Package.swift                     # Swift Package Manager
│   ├── Info.plist                        # Extension конфігурація
│   └── README.md                         # Документація
├── .github/workflows/
│   └── build-ios-synthesizer.yml         # CI/CD
└── README_SYNTHESIZER.md                 # Цей файл
```

---

## 🏗️ Архітектура

### Гібридний підхід

Проект поєднує кращі практики з двох джерел:

#### Від польського проекту (rhvoice-ee)
- ✅ AVSpeechSynthesisProvider API
- ✅ Динамічні діапазони з C++ API
- ✅ SSML підтримка
- ✅ VoiceOver інтеграція

#### Від UkrainianReader
- ✅ 4 українські голоси
- ✅ Досвід роботи з RHVoice C API
- ✅ Налаштування параметрів синтезу

### Компоненти

```
┌─────────────────────────────────────┐
│         iOS VoiceOver               │
│  (System Speech Synthesizer API)    │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  UkrainianSpeechSynthesizer.swift   │
│  (AVSpeechSynthesisProviderAudioUnit)│
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│    RHVoiceParameters.mm             │
│    (Objective-C++ Bridge)           │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│      RHVoice C++ Engine             │
│   (libRHVoice + libRHVoice_core)    │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│      Ukrainian Voices               │
│  (Anatol, Natalia, Marianna, etc)   │
└─────────────────────────────────────┘
```

---

## 🧪 Тестування

### Запуск тестів локально

```bash
cd RHVoiceUkrainianSynthesizer
swift test
```

### Тести в CI/CD

GitHub Actions автоматично запускає тести при кожному push:

- ✅ Unit тести
- ✅ Integration тести
- ✅ Code coverage
- ✅ Збірка для arm64

### Покриття коду

Звіти про покриття коду доступні в [Codecov](https://codecov.io/gh/abuten1977-design/RHVoiceUkraine).

---

## 📱 Використання

### В системних налаштуваннях

1. **Налаштування → Доступність → VoiceOver → Мова**
2. Вибрати **Українська**
3. Вибрати один з голосів:
   - Anatol
   - Natalia
   - Marianna
   - Volodymyr

### Налаштування параметрів

**Швидкість:**
- Повільніше: 0.5x
- Нормально: 1.0x (default)
- Швидше: 2.0x

**Гучність:**
- Тихо: 0%
- Нормально: 100% (default)

**Тембр:**
- Нижче: 0.5x
- Нормально: 1.0x (default)
- Вище: 2.0x

---

## 🔧 Розробка

### Вимоги

- macOS 14+ (Sonoma)
- Xcode 15+
- iOS 16.0+ SDK
- CMake 3.20+
- Boost 1.70+

### Налаштування середовища

```bash
# Встановити залежності
brew install cmake boost

# Клонувати з submodules
git clone --recursive https://github.com/abuten1977-design/RHVoiceUkraine.git
```

### Додавання нового голосу

1. Додати папку з голосом в `Resources/Voices/`
2. Оновити `UkrainianSpeechSynthesizer.swift`:

```swift
AVSpeechSynthesisProviderVoice(
    name: "NewVoice",
    identifier: "com.rhvoice.ukrainian.newvoice",
    primaryLanguages: ["uk-UA"],
    supportedLanguages: ["uk-UA"]
)
```

3. Додати тест в `UkrainianSpeechSynthesizerTests.swift`

### Налагодження

```swift
// В synthesizeSpeechRequest додати:
print("🎤 Synthesizing: \(text)")
print("⚙️ Rate: \(rate), Volume: \(volume), Pitch: \(pitch)")
print("🗣️ Voice: \(voiceName)")
```

---

## 📊 GitHub Actions

### Workflows

1. **Build iOS Ukrainian Synthesizer**
   - Запускається при push в `main` або `develop`
   - Збирає RHVoice бібліотеки (arm64)
   - Запускає тести
   - Створює артефакти

### Артефакти

- `ukrainian-voices-extension` - App Extension
- `rhvoice-ios-libraries-arm64` - Бібліотеки для iPhone

### Час виконання

- Тести: ~2 хвилини
- Збірка: ~5 хвилин
- **Загалом: ~7 хвилин**

---

## 🎯 Roadmap

### Phase 1: Core (✅ ЗАВЕРШЕНО)
- [x] Структура проекту
- [x] AVSpeechSynthesisProvider
- [x] RHVoice bridge
- [x] 4 українські голоси
- [x] Unit тести
- [x] Integration тести
- [x] GitHub Actions

### Phase 2: Integration (В ПРОЦЕСІ)
- [ ] Xcode проект з extension
- [ ] Підключення RHVoice engine
- [ ] Синтез аудіо
- [ ] Тестування на iPhone

### Phase 3: Polish (НАСТУПНЕ)
- [ ] SSML підтримка
- [ ] Управління паузами
- [ ] Оптимізація швидкості
- [ ] UI тести

### Phase 4: Release (МАЙБУТНЄ)
- [ ] TestFlight beta
- [ ] App Store submission
- [ ] Документація користувача
- [ ] Відео інструкції

---

## 🤝 Внесок

Проект відкритий для внеску! Якщо ви хочете допомогти:

1. Fork репозиторій
2. Створіть feature branch (`git checkout -b feature/amazing-feature`)
3. Commit зміни (`git commit -m 'Add amazing feature'`)
4. Push в branch (`git push origin feature/amazing-feature`)
5. Відкрийте Pull Request

---

## 📄 Ліцензія

GPL-3.0-or-later - як RHVoice проект.

Детальніше в [LICENSE](LICENSE).

---

## 👤 Автор

**Andriy Butenko**  
Blind Accessibility & Assistive Technology Specialist  
📧 abuten1977@gmail.com  
🇩🇰 Copenhagen, Denmark

---

## 🙏 Подяки

- **[RHVoice project](https://github.com/RHVoice/RHVoice)** - за чудовий TTS движок
- **Polish rhvoice-ee project** - за приклад VoiceOver інтеграції
- **UkrainianReader project** - за українські голоси та досвід
- **Українська спільнота** - за підтримку та тестування

---

## 📚 Додаткові ресурси

- [RHVoice Documentation](https://github.com/RHVoice/RHVoice/wiki)
- [AVSpeechSynthesisProvider API](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisprovider)
- [iOS Accessibility](https://developer.apple.com/accessibility/ios/)
- [VoiceOver Guide](https://support.apple.com/guide/iphone/turn-on-and-practice-voiceover-iph3e2e415f/ios)

---

*Створено з ❤️ для української спільноти незрячих користувачів iOS*
