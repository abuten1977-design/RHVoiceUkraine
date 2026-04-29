# RHVoiceUkraine — Контекст для Gemini
**Дата:** 29.04.2026  
**Ветка:** `ci/macos-gates-2026-04-26`  
**Последний коммит:** `2b4ce7ef` — "Restore outer async + preBuffer 1200"

---

## ЧТО УЖЕ ИСПРАВЛЕНО — НЕ ТРОГАТЬ

### 1. use-after-free (RHVoiceEngine.mm)
`EngineState` теперь `std::shared_ptr`. Producer держит `producerState` — локальную копию shared_ptr. Без этого crash под нагрузкой.
```objc
// Обязательно так:
std::shared_ptr<EngineState> producerState = std::atomic_load(&_activeState);
```

### 2. Формула rate (RHVoiceEngine.mm → buildMessage)
```objc
double polishRate = fmax(0.5, rate * 2.0);  // 0.5→1.0 норма, 1.0→2.0 быстро
p.absolute_rate = (polishRate - 1.0);
p.relative_rate = polishRate;
```
Не менять. Предыдущая формула `0.5 + rate * 1.5` давала неверную скорость.

### 3. Pitch (RHVoiceEngine.mm → buildMessage)
```objc
double polishPitch = 0.5 + pitch * 0.5;  // pitch 0-2 → 0.5-1.5
p.absolute_pitch = (polishPitch - 1.0);
p.relative_pitch = polishPitch;
```

### 4. outer async (UkrainianSpeechSynthesizer.swift → synthesizeSpeechRequest)
```swift
DispatchQueue.global(qos: .userInitiated).async { [weak self] in
    guard let self else { return }
    self.rhvoiceEngine.synthesizeStreaming(...) { samples, count, _ in
        self.audioBuffer.appendSamples(samples, count: count, token: requestToken)
    }
    self.audioBuffer.markCompleted(with: requestToken)  // ВНУТРИ async блока!
}
```
Без outer async — VoiceOver зависает. `markCompleted` ОБЯЗАН быть внутри async блока.

### 5. preBufferFrames = 1200
При 24000 Hz = 50ms. Не ставить ниже 600 — будет choppy/дёрганость.

### 6. Добавлен pitch
- `enum RHVoiceParameter: case pitch = 5`
- `pitchParam` в `AUParameterTree`
- `pitchValue: AUValue = 1.0`
- `pitch: request.settings.pitch` передаётся в `synthesizeStreaming`
- `pitch` в `RHVoiceSpeechSettings` и сохраняется в UserDefaults

---

## ТРИ ОСТАВШИХСЯ ПРОБЛЕМЫ

### ПРОБЛЕМА 1: Щелчки при быстром переключении VoiceOver
**Симптом:** Пользователь быстро двигает курсор VoiceOver → слышны щелчки/артефакты между словами.  
**Что происходит:**
1. VoiceOver вызывает `cancelSpeechRequest()` — `audioBuffer.cancelCurrentRequest()` + `rhvoiceEngine.cancel()`
2. Сразу вызывает `synthesizeSpeechRequest()` — новый запрос
3. Между старым звуком и новым — резкий обрыв → click

**Возможные решения:**
- Fade-out при отмене: применить короткое (4-8ms, ~100-200 frames at 24kHz) линейное затухание в последних фреймах перед тишиной
- Или: в `renderFrames` когда `cancelled` → применять fade вместо резкого обрыва
- Или: гарантировать небольшой crossfade между cancellation и новым буфером

**Осторожно:** Render block (performRender) — НЕЛЬЗЯ mutex/semaphore/usleep.

### ПРОБЛЕМА 2: Задержка перед началом речи (~150-300ms)
**Симптом:** После переключения VoiceOver — заметная пауза до первого звука.  
**Из чего складывается:**
- `cancel()` ждёт завершения предыдущего синтеза — до 300ms (kCancelWaitTimeoutSec = 0.3)
- RHVoice запускает синтез: первые samples появляются через ~50-100ms
- preBuffer: render не стартует пока не накопится 1200 frames (50ms)
- Итого потенциально 400-450ms

**Возможные решения:**
- Уменьшить cancel timeout ещё: 0.3s → 0.15s (риск: незавершённый synthesis в фоне)
- Прогреть движок заранее: в `allocateRenderResources()` добавить `_ = rhvoiceEngine` чтобы lazy init не срабатывал при первом запросе
- Уменьшить preBufferFrames до 800 (33ms) если тесты покажут достаточную плавность

### ПРОБЛЕМА 3: Громкость не меняется
**Симптом:** Слайдер громкости в приложении не влияет на VoiceOver.  
**Подозрение:** App Group не работает в dev-сборке (entitlements не подписаны) → extension не может прочитать snapshot → `base.volume` всегда 1.0 (default).  
**VoiceOver не отправляет volume через AUParameter** — это известное ограничение AVFoundation.

**Диагностика:**
```swift
// Добавь в resolvedRequest:
NSLog("📊 SNAPSHOT volume=%.2f base.volume=%.2f volumeValue=%.2f", 
      snapshot.generalSettings.volume, base.volume, volumeValue)
```
Если base.volume всегда 1.0 — App Group не работает.

**Возможные решения:**
- Проверить entitlements подписаны ли для dev-сборки: `codesign -dv --entitlements - UkrainianVoicesExtensionMac.appex`
- Если App Group работает — проверить что App правильно вызывает `RHVoiceSharedSettingsStore.saveSnapshot()`
- Временный workaround: volume parameter в AUParameterTree — убедиться что VoiceOver не сбрасывает его в 0

---

## АРХИТЕКТУРА (кратко)

```
synthesizeSpeechRequest(request)
  └── resolvedRequest()           ← читает snapshot (App Group) + AUParameter multipliers
  └── rhvoiceEngine.cancel()      ← ждёт до 0.3s
  └── audioBuffer.beginRequest()  ← начинает новый token
  └── DispatchQueue.global.async:
        └── synthesizeStreaming()  ← блокирует background thread пока не синтезирует всё
              └── callback → audioBuffer.appendSamples()  ← копит samples
        └── audioBuffer.markCompleted()

performRender (audio render thread, вызывается ~1000x/sec)
  └── audioBuffer.renderFrames()  ← lock-free, ждёт preBufferFrames перед стартом
```

**Формат данных:** RHVoice → Int16 PCM 24kHz → Float32 (делением на 32768) → VoiceOver

**App Group ID:** `group.rhvoice.UkrainianVoices.shared`  
**Snapshot файл:** `SharedSettingsSnapshot.json` в App Group container

---

## КЛЮЧЕВЫЕ ФАЙЛЫ

| Файл | Роль |
|------|------|
| `UkrainianVoicesApp/Extension/Provider/UkrainianSpeechSynthesizer.swift` | AU + render + synthesis dispatch |
| `RHVoiceKit/Sources/RHVoiceEngine.mm` | C++ мост, streaming, buffer (Obj-C++ класс RHVoiceEngine + RHVoiceAudioBuffer) |
| `UkrainianVoicesApp/Shared/RHVoiceSharedSettings.swift` | App Group, snapshot, settings model |
| `UkrainianVoicesApp/App/ContentView.swift` | UI слайдеры (rate/volume/pitch) |

---

## ЗАПРЕЩЕНО

- Mutex/semaphore/usleep в `performRender`
- Убирать outer async из `synthesizeSpeechRequest`
- Ставить markCompleted вне async блока
- Ставить preBufferFrames ниже 600
- Менять формулу `polishRate = fmax(0.5, rate * 2.0)`
- Упрощать `std::shared_ptr<EngineState>` → сырой указатель
