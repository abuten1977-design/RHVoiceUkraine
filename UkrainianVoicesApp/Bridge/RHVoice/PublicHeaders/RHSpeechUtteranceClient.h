//
//  RHSpeechUtteranceClient.h
//  RHVoice
//
//  Created by Ihor Shevchuk on 12.09.2022.
//

#import <Foundation/Foundation.h>

@class RHSpeechSynthesisMarker;
@class RHSpeechUtteranceClient;

@protocol RHSpeechUtteranceClientMarkerDelegate <NSObject>
- (void)utteranceClientDidReceiveMarkers:(NSArray<RHSpeechSynthesisMarker *> *_Nonnull)markers;
- (void)utteranceClientDidReceiveSamples:(const short* _Nonnull)samples withSize:(NSInteger)count;
@end


typedef enum RHSpeechUtteranceClientStatus : NSInteger {
    RHSpeechUtteranceClientStatusCreated,
    RHSpeechUtteranceClientStatusRendering,
    RHSpeechUtteranceClientStatusCompleted,
    RHSpeechUtteranceClientStatusError,
    RHSpeechUtteranceClientStatusCanceled
} RHSpeechUtteranceClientStatus;

NS_ASSUME_NONNULL_BEGIN

@interface RHSpeechUtteranceClient : NSObject
@property (nonatomic, weak, nullable) id<RHSpeechUtteranceClientMarkerDelegate> markerDelegate;
- (instancetype)initWithAudioBufferSize:(int)audioBufferSize;
- (RHSpeechUtteranceClientStatus)status;
- (BOOL)completed;
- (BOOL)isRendering;
- (void)cancel;
@end

NS_ASSUME_NONNULL_END
