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


#ifndef RHVoiceWrapper_h
#define RHVoiceWrapper_h

#include <memory>
#include <stdexcept>
#include <iostream>
#include <fstream>
#include <iterator>
#include <algorithm>

#include "core/engine.hpp"
#include "core/document.hpp"
#include "core/client.hpp"
#include "audio.hpp"

namespace RHVoice {

class audio_player: public RHVoice::client
{
public:
    explicit audio_player(const std::string& path);
    bool play_speech(const short* samples,std::size_t count);
    void finish();
    bool set_sample_rate(int sample_rate);
    bool set_buffer_size(unsigned int buffer_size);
    
private:
    RHVoice::audio::playback_stream stream;
};

}
#endif /* RHVoiceWrapper_h */
