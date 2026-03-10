# 🇺🇦 Ukrainian Voices for iOS

**Українські голоси для VoiceOver на iPhone**

iOS додаток з 4 українськими голосами для системного VoiceOver.

---

## 📱 Встановлення

### Через IPA (з GitHub Actions)

1. Завантажити `UkrainianVoices.ipa` з GitHub Actions artifacts
2. Встановити через Xcode:
   ```bash
   # Підключити iPhone
   # Перетягнути .ipa в Xcode → Devices and Simulators
   ```
3. Або через iTunes/Finder
4. Довірити сертифікат розробника на iPhone:
   - Налаштування → Основні → VPN та керування пристроєм → Довіряти

### Активація голосів

1. Відкрити **Налаштування**
2. **Доступність** → **VoiceOver** → **Мова**
3. Вибрати **Українська**
4. Вибрати один з голосів:
   - Anatol (чоловічий)
   - Natalia (жіночий)
   - Marianna (жіночий)
   - Volodymyr (чоловічий)

---

## 🏗️ Структура

```
UkrainianVoicesApp/
├── App/                              # iOS додаток (host)
│   ├── UkrainianVoicesApp.swift     # Головний файл
│   ├── ContentView.swift            # UI
│   └── Info.plist
├── Extension/                        # VoiceOver Extension
│   ├── Provider/
│   │   └── UkrainianSpeechSynthesizer.swift
│   ├── Bridge/
│   │   ├── RHVoiceParameters.h
│   │   └── RHVoiceParameters.mm
│   ├── Resources/Voices/            # 4 українські голоси
│   ├── Libraries/                   # RHVoice бібліотеки (arm64)
│   └── Info.plist
├── Tests/                           # Автоматичні тести
│   ├── RHVoiceParametersTests.swift
│   └── UkrainianSpeechSynthesizerTests.swift
├── Makefile                         # Команди збірки
└── README.md
```

---

## 🔨 Збірка

### Локально

```bash
# Зібрати для iPhone
make build

# Запустити тести
make test

# Створити IPA
make ipa
```

### GitHub Actions

Автоматична збірка при push:
- ✅ Запуск тестів
- ✅ Збірка RHVoice бібліотек (arm64)
- ✅ Створення .ipa файлу
- ✅ Завантаження артефактів

---

## 🧪 Тестування

### Автоматичні тести

```bash
cd UkrainianVoicesApp
swift test
```

**Unit тести:**
- Параметри (rate, volume, pitch)
- Діапазони значень

**Integration тести:**
- Наявність голосів
- VoiceOver provider
- Обробка запитів

### Тестування на iPhone

1. Встановити .ipa
2. Активувати VoiceOver (потрійне натискання Home/Power)
3. Вибрати український голос
4. Перевірити озвучку

---

## 🎚️ Параметри

### Швидкість (Rate)
- Діапазон: 0.5x - 2.0x
- Default: 1.0x

### Гучність (Volume)
- Діапазон: 0% - 100%
- Default: 100%

### Тембр (Pitch)
- Діапазон: 0.5x - 2.0x
- Default: 1.0x

---

## 🗣️ Голоси

| Ім'я | Стать | Якість |
|------|-------|--------|
| Anatol | Чоловічий | 16/24 kHz |
| Natalia | Жіночий | 16/24 kHz |
| Marianna | Жіночий | 16/24 kHz |
| Volodymyr | Чоловічий | 16/24 kHz |

---

## 🔧 Розробка

### Вимоги

- macOS 14+
- Xcode 15+
- iOS 16.0+ SDK
- CMake 3.20+
- Boost 1.70+

### Архітектура

```
iOS VoiceOver
    ↓
UkrainianSpeechSynthesizer (AVSpeechSynthesisProviderAudioUnit)
    ↓
RHVoiceEngineWrapper (асинхронний)
    ↓
RHVoice C++ Engine
    ↓
Ukrainian Voices
    ↓
Audio Output
```

### Асинхронний синтез

```swift
synthesisQueue.async { [weak self] in
    // Синтез в фоновому потоці
    if let buffer = self.rhvoiceEngine.synthesize(...) {
        self.audioBuffer = buffer
    }
}
```

---

## 📄 Ліцензія

GPL-3.0-or-later (як RHVoice)

---

## 👤 Автор

**Andriy Butenko**  
📧 abuten1977@gmail.com  
🇩🇰 Copenhagen, Denmark

---

*Створено з ❤️ для української спільноти*
