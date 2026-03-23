//
//  RHVoiceBridgeParams+Private.h
//  RHVoice
//
//  Created by Ihor Shevchuk on 12/7/24.
//
//  Copyright (C) 2025  Non-Routine LLC (contact@nonroutine.com)

#ifndef RHVoiceBridgeParams_Private_h
#define RHVoiceBridgeParams_Private_h

#import "RHVoiceBridgeParams.h"

#include "core/event_logger.hpp"

@interface RHVoiceBridgeParams(private_additions)
- (std::shared_ptr<RHVoice::event_logger>)rhLogger;
@end

#endif /* RHVoiceBridge_Private_h */
