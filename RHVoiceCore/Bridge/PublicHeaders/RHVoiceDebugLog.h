#ifndef RHVoiceDebugLog_h
#define RHVoiceDebugLog_h

#ifdef __cplusplus
extern "C" {
#endif

void RHVoiceDebugLogWrite(const char* format, ...) __attribute__((format(printf, 1, 2)));
void RHVoiceDebugLogString(const char* message);
void RHVoiceDebugLogClear(void);

#ifdef __cplusplus
}
#endif

#endif
