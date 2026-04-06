# Чек-лист перед компиляцией (PRE-BUILD CHECKLIST)

Перед каждым запуском сборки (Build) я, ИИ-кодер (Kiro), обязан проверить:
- [ ] **Синтаксис:** Нет ли пропущенных скобок, опечаток или неразрешенных конфликтов слияния (merge conflicts)?
- [ ] **Правила ARC:** Везде ли корректно используются `__bridge_retained` (при передаче NSData в C++) и `__bridge_transfer` (при возврате из C++)? Нет ли риска утечек памяти?
- [ ] **Потокобезопасность:** Нет ли синхронных блокировок (locks/mutex) внутри `internalRenderBlock`? Исключены ли функции `usleep` в аудиопотоке?
- [ ] **VoiceOver UI:** Применены ли трейты `.adjustable` ко всем слайдерам?

**Только после того, как все 4 пункта подтверждены по коду, разрешается запускать сборку.**

---

## Конкретные файлы для проверки:

### 1. RHVoiceEngine.mm
- `play_speech_callback`: использует `__bridge_retained` для передачи NSData в C++ буфер
- `synthesizeStreaming:`: использует `__bridge_transfer` для возврата NSData из C++ буфера
- `ThreadSafeRingBuffer<void*, 1024>`: нет блокировок в push/pop

### 2. UkrainianSpeechSynthesizer.swift
- `internalRenderBlock`: НЕТ `usleep`, НЕТ циклов ожидания
- Возвращает тишину если данных нет
- `outputDataQueue.sync`: только для чтения данных, не для ожидания

### 3. ContentView.swift и SettingsView.swift
- Все `Slider` имеют `.accessibilityAddTraits(.isAdjustable)`
- Все `Slider` имеют `.accessibilityLabel`, `.accessibilityValue`, `.accessibilityHint`

### 4. Package.swift
- Добавлена зависимость `sentry-cocoa`
- Sentry инициализирован в `UkrainianVoicesApp.swift`

---

## Если найдена ошибка:
1. **НЕ КОМПИЛИРОВАТЬ**
2. Исправить ошибку
3. Вернуться к чек-листу
4. Проверить все пункты снова
5. Только потом компилировать
