# iOS Audit Roadmap

## Priority 1: Fallback for empty voice list
- File: UkrainianSpeechSynthesizer.swift, speechVoices getter
- Problem: if settings unreadable, returns empty array, VoiceOver sees no voices
- Fix: if filtered list empty, return Self.staticVoices

## Priority 2: Fade-out too aggressive for short phrases
- File: UkrainianSpeechSynthesizer.swift, performRender
- Problem: 128-sample fade silences short utterances (single chars)
- Fix: fade = min(32, toCopy/4). No fade if total frames < 256

## Priority 3: Duplicate linking (static libs + framework)
- File: project.yml, UkrainianVoicesExtension target
- Problem: links -lRHVoice -lRHVoice_core -lRHVoice_audio AND depends on RHVoiceKit framework
- Fix: remove RHVoiceKit framework dependency from extension (keep static libs only)

## Priority 4: Hybrid streaming for iOS (main fix for VoiceOver silence)
- File: UkrainianSpeechSynthesizer.swift, synthesizeSpeechRequest + performRender
- Problem: sync synthesis blocks too long, VoiceOver times out
- Fix: synthesize on background thread, feed chunks to render via lock-free buffer
- Note: keep macOS sync path working (use #if os(iOS) or runtime check)

## Priority 5: Replace NSLock with os_unfair_lock or atomic buffer
- File: UkrainianSpeechSynthesizer.swift
- Problem: NSLock causes priority inversion on audio thread
- Fix: use os_unfair_lock (acceptable for short critical sections) or lock-free SPSC ring buffer
- Note: if Priority 4 uses lock-free buffer, this is solved automatically
