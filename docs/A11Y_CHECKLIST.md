# A11Y checklist for every changed screen

Run this before a build that changes an app screen.  Objective checks (labels,
values, actions, build and tests) come first; the final VoiceOver pass is on a
physical device.

1. VoiceOver order is logical: title, fields, helper controls, Save, Cancel.
2. A newly opened form places VoiceOver focus on its first editable field.
3. Every toggle exposes and immediately announces its new value: `Увімкнено`
   or `Вимкнено`.
4. Every action gives an immediate spoken result, not only a status line far
   away on the screen.
5. Each hint is adjacent to its control or is the control's accessibility hint.
6. Destructive and secondary actions, including Delete and Share, are exposed
   as named VoiceOver actions, not only as swipe gestures.
7. Expandable sections expose and announce `Розгорнуто` or `Згорнуто`.
8. Every interactive element has a Ukrainian, meaningful label; none is read
   only as “button” or as an unexplained English identifier.

Record the physical-device VoiceOver result in the relevant task handoff.
