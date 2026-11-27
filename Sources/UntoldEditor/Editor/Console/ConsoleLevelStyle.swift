//
//  ConsoleLevelStyle.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Foundation
import SwiftUI
import UntoldEngine

/// How a row shows its level, from the mockup: the glyph in its tint, the
/// message's colour, a tinted background behind an error; and the row's time
/// and source texts.
enum ConsoleLevelStyle {
    static func glyph(for level: LogLevel) -> String {
        switch level {
        case .error: return "circle.fill"
        case .warning: return "triangle.fill"
        case .info: return "info.circle"
        case .debug: return "circle.dashed"
        case .test: return "checkmark.circle"
        case .none: return "circle"
        }
    }

    static func glyphColor(for level: LogLevel) -> Color {
        switch level {
        case .error: return .editorError
        case .warning: return .editorWarning
        case .info: return .editorTextSecondary
        case .debug: return .editorTextTertiary
        case .test: return .editorSuccess
        case .none: return .editorTextTertiary
        }
    }

    static func messageColor(for level: LogLevel) -> Color {
        switch level {
        case .error: return .editorErrorText
        case .warning: return .editorWarningText
        case .debug: return .editorTextTertiary
        case .info, .test, .none: return .editorTextPrimary
        }
    }

    static func rowBackground(for level: LogLevel) -> Color {
        level == .error ? .editorErrorRowBackground : .clear
    }

    /// The row's time, to the second: the mockup's 70 pt column.
    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// "File.swift:line", or nothing when the message carries no file.
    static func source(file: String, line: Int) -> String {
        let name = URL(fileURLWithPath: file).lastPathComponent
        guard file.isEmpty == false, name.isEmpty == false else { return "" }
        return "\(name):\(line)"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
