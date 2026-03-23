//
//  RHVoiceBridge.m
//  RHVoice
//
//  Created by Ihor Shevchuk on 02.05.2022.
//
//
//  Copyright (C) 2022–2024 Ihor Shevchuk
//  Copyright (C) 2025 Non-Routine LLC
//  Contact: contact@nonroutine.com
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

#import "RHVoiceBridge.h"

#import "RHVoiceBridge+PrivateAdditions.h"
#import "RHLanguage+Private.h"
#import "RHVoiceBridgeParams+Private.h"

#import <AVFAudio/AVAudioSession.h>
#import <AVFAudio/AVAudioPlayer.h>
#import <AVFAudio/AVSpeechSynthesis.h>

#import "NSFileManager+Additions.h"
#import "NSString+Additions.h"
#import "NSString+stdStringAddtitons.h"
#import "RHVoiceLogger.h"
#import "RHSpeechSynthesisVoice.h"

#include "core/engine.hpp"
#include "core/package_client.hpp"
#include "../../Core/src/include/RHVoice.h"

@interface RHVoiceBridge () {
    std::shared_ptr<RHVoice::engine> RHEngine;
}
@end

@implementation RHVoiceBridge

#pragma mark - Public

+ (instancetype)sharedInstance {
    static RHVoiceBridge *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[RHVoiceBridge alloc] init];
    });
    return sharedInstance;
}

- (void)setParams:(RHVoiceBridgeParams *)params {
    if(![self.params isEqual:params]) {
        _params = params;
    }
}

- (NSString *)version {
    return STDStringToNSString(RHVoice_get_version());
}

- (NSArray <RHLanguage *> *)languages {
    if(![self engine].get()) {
        return @[];
    }
    NSMutableArray *result = [[NSMutableArray alloc] init];
    const RHVoice::language_list& languages = [self engine]->get_languages();
    for (auto language =languages.begin(); language != languages.end(); ++language) {
        [result addObject:[[RHLanguage alloc] initWith:*language]];
    }
    return [result copy];
}

- (BOOL)configureWithKey:(NSString *)key
                andValue:(NSString *)value {
    return [self engine]->configure(NSStringToSTDString(key), NSStringToSTDString(value));
}

#pragma mark - Internal

- (std::shared_ptr<RHVoice::engine>)engine {
    @synchronized (self) {
        if(RHEngine.get() == nil) {
            [self createRHEngineWithParams:self.params];
        }
        
        return RHEngine;
    }
}

- (NSString *)packagesJSON {
    RHVoice::pkg::package_client::ptr packageClient;
    if([self engine].get()) {
        packageClient = [self engine]->get_package_client();
    }
    
    if(packageClient.get()) {
        return STDStringToNSString(packageClient->get_dir_as_string());
    }
    return  @"";
}

- (NSString *)cachedPackagesJSON {
    RHVoice::pkg::package_client::ptr packageClient = [self engine]->get_package_client();
    if(packageClient.get()) {
        return STDStringToNSString(packageClient->get_cached_dir_as_string());
    }
    return @"";
}

- (NSString *)onlinePackagesJSON {
    RHVoice::pkg::package_client::ptr packageClient = [self engine]->get_package_client();
    if(packageClient.get()) {
        try {
            return STDStringToNSString(packageClient->get_dir_from_server_as_string());
        } catch (...) {
            [RHVoiceLogger logAtLevel:RHVoiceLogLevelError format:@"Failed to fetch packages.json from server. Falling back to cache if available."];
        }
    }
    return @"";
}

- (void)recreateEngine {
    @synchronized (self) {
        RHEngine.reset();
        [self engine];
    }
}

#pragma mark - Private

+ (void)load {
    [[NSFileManager defaultManager] RHRemoveTempFolderIfNeededPath:[NSString RHTemporaryFolderPath]];
}

- (instancetype)init {
    self = [super init];
    if(self) {
        self.params = [RHVoiceBridgeParams defaultParams];
    }
    return self;
}

- (void)createRHEngineWithParams:(RHVoiceBridgeParams *)params {
    try {
        RHVoice::engine::init_params param;
        param.data_path = NSStringToSTDString(params.dataPath);
        param.config_path = NSStringToSTDString(params.configPath);
        param.pkg_path = NSStringToSTDString(params.pkgPath);
        param.logger = params.rhLogger;
        
        RHEngine = RHVoice::engine::create(param);
    } catch (...) {
        [RHVoiceLogger logAtLevel:RHVoiceLogLevelError format:@"No Languages folder is located at: %@", params.dataPath];
        [RHVoiceLogger logAtLevel:RHVoiceLogLevelError format:@"Please set  valid 'dataPath' property. This folder has to contain 'languages' and 'voices' folders."];
    }
}

- (const RHVoice::voice_list &)voices {
    return [self engine]->get_voices();
}

@end
