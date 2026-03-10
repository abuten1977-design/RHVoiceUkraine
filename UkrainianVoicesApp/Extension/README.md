# RHVoice Ukrainian Synthesizer

**Ukrainian Speech Synthesizer for iOS VoiceOver**

Інтеграція українських голосів RHVoice з системою VoiceOver на iOS.

## 🎯 Особливості

- 🇺🇦 **4 українські голоси:** Anatol, Natalia, Marianna, Volodymyr
- ♿ **VoiceOver інтеграція:** Повна підтримка системного VoiceOver
- 🎚️ **Управління параметрами:**
  - Швидкість (rate): 0.5x - 2.0x
  - Гучність (volume): 0% - 100%
  - Тембр (pitch): 0.5x - 2.0x
- 📱 **iOS 16+:** Використовує AVSpeechSynthesisProvider API
- ✅ **Тести:** Unit та Integration тести

## 📁 Структура проекту

```
RHVoiceUkrainianSynthesizer/
├── Provider/
│   └── UkrainianSpeechSynthesizer.swift    # VoiceOver provider
├── Bridge/
│   ├── RHVoiceParameters.h                 # Objective-C заголовок
│   └── RHVoiceParameters.mm                # Objective-C++ реалізація
├── Resources/
│   └── Voices/                             # Українські голоси
│       ├── anatol/
│       ├── natalia/
│       ├── marianna/
│       └── volodymyr/
├── Tests/
│   ├── RHVoiceParametersTests.swift        # Unit тести
│   └── UkrainianSpeechSynthesizerTests.swift # Integration тести
├── Info.plist                              # App Extension конфігурація
└── README.md                               # Ця документація
```

## 🏗️ Архітектура

### Гібридний підхід

Проект поєднує кращі практики з двох джерел:

**Від польського проекту (rhvoice-ee):**
- ✅ AVSpeechSynthesisProvider для VoiceOver
- ✅ Динамічні діапазони параметрів з C++ API
- ✅ SSML підтримка

**Від UkrainianReader:**
- ✅ Українські голоси (Anatol, Natalia, Marianna, Volodymyr)
- ✅ Досвід роботи з RHVoice C API
- ✅ Налаштування параметрів синтезу

### Компоненти

1. **UkrainianSpeechSynthesizer** (Swift)
   - Реалізує AVSpeechSynthesisProviderAudioUnit
   - Обробляє запити від VoiceOver
   - Управляє параметрами синтезу

2. **RHVoiceParameters** (Objective-C++)
   - Міст між Swift та C++ API RHVoice
   - Читає динамічні діапазони з core/params.hpp
   - Надає параметри для volume, rate, pitch

3. **Voices** (Resources)
   - 4 українські голоси
   - Повні мовні дані для української мови

## 🧪 Тестування

### Unit Tests

```bash
# Тестують окремі компоненти
- RHVoiceParametersTests: Перевірка параметрів (min/max/default)
```

### Integration Tests

```bash
# Тестують інтеграцію з VoiceOver
- UkrainianSpeechSynthesizerTests: Перевірка голосів та provider
```

### Запуск тестів

```bash
# Через Xcode
⌘ + U

# Через xcodebuild
xcodebuild test -scheme RHVoiceUkrainianSynthesizer -destination 'platform=iOS Simulator,name=iPhone 15'
```

## 📦 Збірка

### Вимоги

- Xcode 15+
- iOS 16.0+ SDK
- RHVoice libraries (libRHVoice.dylib, libRHVoice_core.dylib, libRHVoice_audio.dylib)

### Локальна збірка

```bash
# 1. Зібрати RHVoice бібліотеки
cd ../RHVoice
./build_ios.sh

# 2. Зібрати extension
xcodebuild -project RHVoiceUkrainianSynthesizer.xcodeproj \
           -scheme RHVoiceUkrainianSynthesizer \
           -sdk iphoneos \
           -configuration Release
```

### GitHub Actions

Автоматична збірка налаштована в `.github/workflows/build-ios-synthesizer.yml`

## 📱 Встановлення

### На фізичний iPhone

1. Зібрати проект в Xcode
2. Підключити iPhone
3. Запустити на пристрої
4. Відкрити **Налаштування → Доступність → VoiceOver → Мова**
5. Вибрати **Українська → Ukrainian Voices**

### Через TestFlight

1. Зібрати .ipa через GitHub Actions
2. Завантажити в App Store Connect
3. Додати тестерів
4. Встановити через TestFlight

## 🎚️ Параметри

### Швидкість (Rate)

```swift
// Діапазон: 0.5x - 2.0x
// Default: 1.0x (нормальна швидкість)
let params = RHVoiceParameters.rateParameters()
print("Min: \(params.min), Max: \(params.max), Default: \(params.defaultValue)")
```

### Гучність (Volume)

```swift
// Діапазон: 0.0 - 1.0 (0% - 100%)
// Default: 1.0 (максимальна гучність)
let params = RHVoiceParameters.volumeParameters()
```

### Тембр (Pitch)

```swift
// Діапазон: 0.5x - 2.0x
// Default: 1.0x (нормальний тембр)
let params = RHVoiceParameters.pitchParameters()
```

## 🔧 Розробка

### Додавання нового голосу

1. Додати папку з голосом в `Resources/Voices/`
2. Додати голос в `UkrainianSpeechSynthesizer.speechVoices`:

```swift
AVSpeechSynthesisProviderVoice(
    name: "NewVoice",
    identifier: "com.rhvoice.ukrainian.newvoice",
    primaryLanguages: ["uk-UA"],
    supportedLanguages: ["uk-UA"]
)
```

### Налагодження

```swift
// Додати логування в synthesizeSpeechRequest
print("Synthesizing: \(text)")
print("Rate: \(rate), Volume: \(volume), Pitch: \(pitch)")
```

## 📄 Ліцензія

GPL-3.0-or-later (як RHVoice)

## 👤 Автор

Andriy Butenko  
📧 abuten1977@gmail.com

## 🙏 Подяки

- **RHVoice project** - за чудовий TTS движок
- **Polish rhvoice-ee project** - за приклад VoiceOver інтеграції
- **UkrainianReader project** - за українські голоси

---

*Створено з ❤️ для української спільноти*
