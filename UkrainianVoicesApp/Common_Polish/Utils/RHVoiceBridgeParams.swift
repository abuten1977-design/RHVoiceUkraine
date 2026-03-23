//
//  RHVoiceBridgeParams.swift
//  RHVoice
//
//  Created by Ihor Shevchuk on 12/29/24.
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

import RHVoice

extension RHVoiceBridgeParams {
    public static var iOSDefault: RHVoiceBridgeParams {
        let initParams = RHVoiceBridgeParams.default()
        if let dataPath = FileManager.default.rhvoiceDataPathURL?.path(percentEncoded: false) {
            initParams.dataPath = dataPath
        }
        
        if let configPath = FileManager.default.rhvoiceConfigFolderPathURL?.path(percentEncoded: false) {
            initParams.configPath = configPath
        }
        
        if let pkgPath = FileManager.default.rhvoicePackagePathURL?.path(percentEncoded: false) {
            initParams.pkgPath = pkgPath
        }
        return initParams
    }
}
