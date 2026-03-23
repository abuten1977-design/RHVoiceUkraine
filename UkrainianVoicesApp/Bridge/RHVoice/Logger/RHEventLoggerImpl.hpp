//
//  RHEventLoggerImpl.hpp
//  RHVoice
//
//  Created by Ihor Shevchuk on 04.05.2022.
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

#ifndef RHEventLoggerImpl_hpp
#define RHEventLoggerImpl_hpp

#include <stdio.h>

#include "core/event_logger.hpp"

class RHEventLoggerImpl : public RHVoice::event_logger
{
public:
    void log(const std::string& tag, RHVoice_log_level level, const std::string& message) const override;
};

#endif /* RHeventLoggerImpl_hpp */
