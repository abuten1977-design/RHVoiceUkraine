#import <Foundation/Foundation.h>
#include <stdarg.h>
#include "RHVoiceDebugLog.h"

static NSString* _logPath = nil;
static NSFileHandle* _logHandle = nil;
static dispatch_queue_t _logQueue = nil;

static void ensureLogFile(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _logQueue = dispatch_queue_create("com.rhvoice.debuglog", DISPATCH_QUEUE_SERIAL);
        NSURL* groupURL = [[NSFileManager defaultManager]
            containerURLForSecurityApplicationGroupIdentifier:@"group.rhvoice.UkrainianVoices.shared"];
        if (!groupURL) return;
        _logPath = [[groupURL path] stringByAppendingPathComponent:@"RHVoiceDebug.log"];

        // Truncate if > 1MB
        NSFileManager* fm = [NSFileManager defaultManager];
        NSDictionary* attrs = [fm attributesOfItemAtPath:_logPath error:nil];
        if ([attrs fileSize] > 1024*1024) {
            [fm removeItemAtPath:_logPath error:nil];
        }

        if (![fm fileExistsAtPath:_logPath]) {
            [fm createFileAtPath:_logPath contents:nil attributes:nil];
        }
        _logHandle = [NSFileHandle fileHandleForWritingAtPath:_logPath];
        [_logHandle seekToEndOfFile];
    });
}

void RHVoiceDebugLogWrite(const char* format, ...) {
    ensureLogFile();
    if (!_logHandle || !_logQueue) return;

    va_list args;
    va_start(args, format);
    NSString* msg = [[NSString alloc] initWithFormat:[NSString stringWithUTF8String:format] arguments:args];
    va_end(args);

    NSDateFormatter* df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"HH:mm:ss.SSS";
    NSString* ts = [df stringFromDate:[NSDate date]];
    NSString* line = [NSString stringWithFormat:@"%@ [%d] %@\n", ts, (int)getpid(), msg];

    dispatch_async(_logQueue, ^{
        NSData* data = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (data) [_logHandle writeData:data];
    });

    if ([msg containsString:@"LATENCY_DIAG"] || [msg containsString:@"PARAMS"]) {
        NSLog(@"%@", msg);
    }
}

void RHVoiceDebugLogString(const char* message) {
    RHVoiceDebugLogWrite("%s", message);
}

void RHVoiceDebugLogClear(void) {
    ensureLogFile();
    if (!_logHandle || !_logQueue) return;

    dispatch_sync(_logQueue, ^{
        [_logHandle truncateFileAtOffset:0];
        [_logHandle seekToFileOffset:0];
    });
}
