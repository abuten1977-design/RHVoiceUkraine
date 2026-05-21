//
//  RHVoiceStreamingClient.mm
//  RHVoiceBridge
//

#import "RHVoiceStreamingClient.h"
#import "RHVoiceEngine.h"

@interface RHVoiceStreamingClient ()
@property (nonatomic, strong) RHVoiceEngine *engine;
@property (nonatomic, assign) RHVoiceStreamingClientStatus internalStatus;
@property (nonatomic, strong) NSLock *statusLock;
@property (nonatomic, strong) dispatch_queue_t synthesisQueue;
@end

@implementation RHVoiceStreamingClient

- (instancetype)initWithEngine:(RHVoiceEngine *)engine {
    self = [super init];
    if (self) {
        _engine = engine;
        _internalStatus = RHVoiceStreamingClientStatusCreated;
        _statusLock = [[NSLock alloc] init];
        _synthesisQueue = dispatch_queue_create("com.rhvoice.ukrainianvoices.streaming-client",
                                                dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,
                                                                                       QOS_CLASS_USER_INITIATED,
                                                                                       0));
    }
    return self;
}

- (RHVoiceStreamingClientStatus)status {
    [self.statusLock lock];
    RHVoiceStreamingClientStatus status = self.internalStatus;
    [self.statusLock unlock];
    return status;
}

- (void)setStatusLocked:(RHVoiceStreamingClientStatus)status {
    [self.statusLock lock];
    self.internalStatus = status;
    [self.statusLock unlock];
}

- (BOOL)completed {
    RHVoiceStreamingClientStatus status = [self status];
    return status == RHVoiceStreamingClientStatusCompleted ||
           status == RHVoiceStreamingClientStatusCanceled ||
           status == RHVoiceStreamingClientStatusError;
}

- (void)synthesize:(NSString *)text
             voice:(NSString *)voiceName
              rate:(double)rate
            volume:(double)volume
             pitch:(double)pitch {
    if (text.length == 0 || voiceName.length == 0) {
        [self setStatusLocked:RHVoiceStreamingClientStatusError];
        return;
    }

    [self setStatusLocked:RHVoiceStreamingClientStatusRendering];

    NSString *textCopy = [text copy];
    NSString *voiceCopy = [voiceName copy];
    __weak RHVoiceStreamingClient *weakSelf = self;

    dispatch_async(self.synthesisQueue, ^{
        __strong RHVoiceStreamingClient *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        [strongSelf.engine synthesizeStreaming:textCopy
                                         voice:voiceCopy
                                          rate:rate
                                        volume:volume
                                         pitch:pitch
                                       onChunk:^(const short *samples, unsigned int count, int sampleRate) {
            __strong RHVoiceStreamingClient *callbackSelf = weakSelf;
            if (!callbackSelf) {
                return;
            }
            if ([callbackSelf status] == RHVoiceStreamingClientStatusCanceled) {
                return;
            }
            id<RHVoiceStreamingClientDelegate> delegate = callbackSelf.delegate;
            if (delegate && samples && count > 0) {
                [delegate streamingClient:callbackSelf didReceiveSamples:samples count:(NSInteger)count];
            }
        }];

        RHVoiceStreamingClientStatus status = [strongSelf status];
        if (status == RHVoiceStreamingClientStatusRendering) {
            [strongSelf setStatusLocked:RHVoiceStreamingClientStatusCompleted];
        }
    });
}

- (void)cancel {
    [self setStatusLocked:RHVoiceStreamingClientStatusCanceled];
    [self.engine cancel];
}

@end
