//
//  RHVoiceWrapper.cpp
//  
//
//  Created by Ihor Shevchuk on 01.02.2023.
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

#include <stdio.h>

#include "RHVoiceWrapper.h"

using namespace RHVoice;

audio_player::audio_player(const std::string& path)
{
    if(!path.empty())
    {
        stream.set_backend(RHVoice::audio::backend_file);
        stream.set_device(path);
    }
}

bool audio_player::set_sample_rate(int sample_rate)
{
    try
    {
        if(stream.is_open()&&(stream.get_sample_rate()!=sample_rate))
            stream.close();
        stream.set_sample_rate(sample_rate);
        return true;
    }
    catch(...)
    {
        return false;
    }
}

bool audio_player::set_buffer_size(unsigned int buffer_size)
{
    try
    {
        if(stream.is_open()&&(stream.get_buffer_size()!=buffer_size))
            stream.close();
        stream.set_buffer_size(buffer_size);
        return true;
    }
    catch(...)
    {
        return false;
    }
}

bool audio_player::play_speech(const short* samples,std::size_t count)
{
    try
    {
        if(!stream.is_open())
            stream.open();
        stream.write(samples,count);
        return true;
    }
    catch(...)
    {
        stream.close();
        return false;
    }
}

void audio_player::finish()
{
    if(stream.is_open())
        stream.drain();
}

