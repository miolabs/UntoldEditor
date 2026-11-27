//
//  ConsoleCounts.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import UntoldEngine

/// How many messages the console holds, in all and per chip.
struct ConsoleCounts: Equatable {
    var all = 0
    var errors = 0
    var warnings = 0
    var info = 0

    init(all: Int = 0, errors: Int = 0, warnings: Int = 0, info: Int = 0) {
        self.all = all
        self.errors = errors
        self.warnings = warnings
        self.info = info
    }

    init(_ events: [LogEvent]) {
        for event in events {
            all += 1
            switch event.level {
            case .error: errors += 1
            case .warning: warnings += 1
            default: info += 1
            }
        }
    }

    func count(for filter: ConsoleLevelFilter) -> Int {
        switch filter {
        case .all: return all
        case .errors: return errors
        case .warnings: return warnings
        case .info: return info
        }
    }
}
