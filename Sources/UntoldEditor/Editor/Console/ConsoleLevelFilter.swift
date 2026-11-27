//
//  ConsoleLevelFilter.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import UntoldEngine

/// What the console's chips filter by: every message, or the errors, the
/// warnings, or everything else (info, debug and test messages).
enum ConsoleLevelFilter: String, CaseIterable, Identifiable {
    case all
    case errors
    case warnings
    case info

    var id: String {
        rawValue
    }

    func matches(_ level: LogLevel) -> Bool {
        switch self {
        case .all: return true
        case .errors: return level == .error
        case .warnings: return level == .warning
        case .info: return level != .error && level != .warning
        }
    }

    /// The chip's label with its count: "All 14", "2 errors", "1 warning", "9 info".
    func label(count: Int) -> String {
        switch self {
        case .all: return "All \(count)"
        case .errors: return count == 1 ? "1 error" : "\(count) errors"
        case .warnings: return count == 1 ? "1 warning" : "\(count) warnings"
        case .info: return "\(count) info"
        }
    }

    /// The chip's glyph, the one the rows of that level carry; none for All.
    var systemImage: String? {
        switch self {
        case .all: return nil
        case .errors: return "circle.fill"
        case .warnings: return "triangle.fill"
        case .info: return "info.circle"
        }
    }

    var help: String {
        switch self {
        case .all: return "Show every message"
        case .errors: return "Show the errors only"
        case .warnings: return "Show the warnings only"
        case .info: return "Show the information messages only"
        }
    }
}
