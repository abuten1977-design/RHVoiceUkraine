//
//  RHVoiceStreamingClient.h
//  RHVoiceBridge
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class RHVoiceEngine;
@class RHVoiceStreamingClient;

typedef NS_ENUM(NSInteger, RHVoiceStreamingClientStatus) {
    RHVoiceStreamingClientStatusCreated,
    RHVoiceStreamingClientStatusRendering,
    RHVoiceStreamingClientStatusCompleted,
    RHVoiceStreamingClientStatusError,
    RHVoiceStreamingClientStatusCanceled
};

@protocol RHVoiceStreamingClientDelegate <NSObject>
- (void)streamingClient:(RHVoiceStreamingClient *)client
      didReceiveSamples:(const short *)samples
                  count:(NSInteger)count;
@end

@interface RHVoiceStreamingClient : NSObject

@property (nonatomic, weak, nullable) id<RHVoiceStreamingClientDelegate> delegate;

- (instancetype)initWithEngine:(RHVoiceEngine *)engine NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (void)synthesize:(NSString *)text
             voice:(NSString *)voiceName
              rate:(double)rate
            volume:(double)volume
             pitch:(double)pitch;
- (RHVoiceStreamingClientStatus)status;
- (BOOL)completed;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
