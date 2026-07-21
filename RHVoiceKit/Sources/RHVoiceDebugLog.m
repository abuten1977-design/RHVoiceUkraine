#import <Foundation/Foundation.h>
#import <os/log.h>
#import <TargetConditionals.h>
#include <stdarg.h>
#include <fcntl.h>
#include <unistd.h>
#include "RHVoiceDebugLog.h"

static NSString* _logPath = nil;
static dispatch_queue_t _logQueue = nil;

static void ensureLogQueue(void) {
    static dispatch_once_t queueOnceToken;
    dispatch_once(&queueOnceToken, ^{
        _logQueue = dispatch_queue_create("com.rhvoice.debuglog", DISPATCH_QUEUE_SERIAL);
    });
}

// Файл пишеться: у DEBUG — завжди; у Release — лише коли користувач увімкнув
// «Розширену діагностику» в застосунку (App Store privacy: без згоди
// прочитаний текст на диск не потрапляє).
static BOOL rhFileLoggingEnabled(void) {
#if DEBUG
    return YES;
#else
    static NSUserDefaults* groupDefaults = nil;
    static dispatch_once_t defaultsOnceToken;
    dispatch_once(&defaultsOnceToken, ^{
#if TARGET_OS_OSX
        NSString* suite = @"5NNZPP8CRR.group.rhvoice.UkrainianVoices.shared";
#else
        NSString* suite = @"group.rhvoice.UkrainianVoices.shared";
#endif
        groupDefaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    });
    return [groupDefaults boolForKey:@"extendedDiagnostics"];
#endif
}

static NSString* currentLogPath(void) {
#if TARGET_OS_OSX
    NSString* groupIdentifier = @"5NNZPP8CRR.group.rhvoice.UkrainianVoices.shared";
#else
    NSString* groupIdentifier = @"group.rhvoice.UkrainianVoices.shared";
#endif
    NSURL* groupURL = [[NSFileManager defaultManager]
        containerURLForSecurityApplicationGroupIdentifier:groupIdentifier];
    if (!groupURL) {
        _logPath = nil;
        return nil;
    }
    _logPath = [[groupURL path] stringByAppendingPathComponent:@"RHVoiceDebug.log"];
    return _logPath;
}

static void trimLogIfNeeded(NSString* path) {
    NSFileManager* fm = [NSFileManager defaultManager];
    NSDictionary* attrs = [fm attributesOfItemAtPath:path error:nil];
    if ([attrs fileSize] > 1024*1024) {
        [fm removeItemAtPath:path error:nil];
    }
}

static BOOL appendLine(NSString* line, BOOL important) {
    NSString* path = currentLogPath();
    if (!path) return NO;
    trimLogIfNeeded(path);

    NSData* data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return NO;

    int fd = open([path fileSystemRepresentation], O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return NO;

    const uint8_t* bytes = data.bytes;
    NSUInteger remaining = data.length;
    while (remaining > 0) {
        ssize_t written = write(fd, bytes, remaining);
        if (written <= 0) {
            close(fd);
            return NO;
        }
        bytes += written;
        remaining -= (NSUInteger)written;
    }
    if (important) fsync(fd);
    close(fd);
    return YES;
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
    BOOL publicDiagnostic = [msg containsString:@"LATENCY_DIAG"] ||
                            [msg containsString:@"PARAMS"] ||
                            [msg containsString:@"EXT_DIAG"];

    if (important) {
        if (publicDiagnostic) {
            os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_INFO, "%{public}@", msg);
        } else {
            NSLog(@"%@", msg);
        }
    }

    if (!rhFileLoggingEnabled()) return;

    ensureLogQueue();
    if (!_logQueue) {
        if (important) {
            NSLog(@"RHVoiceDebugLog unavailable path=%@ queue=%d",
                  _logPath ?: @"nil",
                  _logQueue ? 1 : 0);
        }
        return;
    }

    NSDateFormatter* df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"HH:mm:ss.SSS";
    NSString* ts = [df stringFromDate:[NSDate date]];
    NSString* line = [NSString stringWithFormat:@"%@ [%d] %@\n", ts, (int)getpid(), msg];

    void (^writeBlock)(void) = ^{
        if (!appendLine(line, important) && important) {
            NSLog(@"RHVoiceDebugLog unavailable path=%@ queue=%d",
                  _logPath ?: @"nil",
                  _logQueue ? 1 : 0);
        }
    };
    dispatch_async(_logQueue, writeBlock);
}

void RHVoiceDebugLogString(const char* message) {
    RHVoiceDebugLogWrite("%s", message);
}

void RHVoiceDebugLogClear(void) {
    ensureLogQueue();
    if (!_logQueue) return;

    dispatch_async(_logQueue, ^{
        NSString* path = currentLogPath();
        if (!path) return;
        int fd = open([path fileSystemRepresentation], O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd >= 0) {
            fsync(fd);
            close(fd);
        }
    });
}
