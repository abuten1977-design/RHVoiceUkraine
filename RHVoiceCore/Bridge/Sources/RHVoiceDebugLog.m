#import <Foundation/Foundation.h>
#include <stdarg.h>
#include "RHVoiceDebugLog.h"

static NSString* _logPath = nil;
static NSFileHandle* _logHandle = nil;
static dispatch_queue_t _logQueue = nil;

static void ensureLogFile(void) {
    static dispatch_once_t queueOnceToken;
    dispatch_once(&queueOnceToken, ^{
        _logQueue = dispatch_queue_create("com.rhvoice.debuglog", DISPATCH_QUEUE_SERIAL);
    });
    if (_logHandle || !_logQueue) return;

    dispatch_sync(_logQueue, ^{
        if (_logHandle) return;

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
    va_list args;
    va_start(args, format);
    NSString* msg = [[NSString alloc] initWithFormat:[NSString stringWithUTF8String:format] arguments:args];
    va_end(args);
    BOOL important = [msg containsString:@"LATENCY_DIAG"] ||
                     [msg containsString:@"PARAMS"] ||
                     [msg containsString:@"APP_DIAG"] ||
                     [msg containsString:@"EXT_DIAG"];

    if (important) {
        NSLog(@"%@", msg);
    }

    ensureLogFile();
    if (!_logHandle || !_logQueue) {
        if (important) {
            NSLog(@"RHVoiceDebugLog unavailable path=%@ handle=%d queue=%d",
                  _logPath ?: @"nil",
                  _logHandle ? 1 : 0,
                  _logQueue ? 1 : 0);
        }
        return;
    }

    NSDateFormatter* df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"HH:mm:ss.SSS";
    NSString* ts = [df stringFromDate:[NSDate date]];
    NSString* line = [NSString stringWithFormat:@"%@ [%d] %@\n", ts, (int)getpid(), msg];

    void (^writeBlock)(void) = ^{
        NSData* data = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (data) {
            [_logHandle seekToEndOfFile];
            [_logHandle writeData:data];
            if (important) [_logHandle synchronizeFile];
        }
    };
    if (important) {
        dispatch_sync(_logQueue, writeBlock);
    } else {
        dispatch_async(_logQueue, writeBlock);
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
