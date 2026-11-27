//
//  ConsoleRowView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// One row of the console on the mockup's grid: the time, the level's glyph,
/// the message with its repeat count when it stands for several, and the
/// source file and line at the right. An error row sits on a tinted background.
struct ConsoleRowView: View {
    let row: ConsoleRow

    var body: some View {
        let event = row.event
        let source = ConsoleLevelStyle.source(file: event.file, line: event.line)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(ConsoleLevelStyle.time(event.timestamp))
                .font(EditorType.mono)
                .foregroundColor(.editorTextSecondary)
                .frame(width: 70, alignment: .leading)
            Image(systemName: ConsoleLevelStyle.glyph(for: event.level))
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(ConsoleLevelStyle.glyphColor(for: event.level))
                .frame(width: 14)
            Text(event.message)
                .font(EditorType.mono)
                .foregroundColor(ConsoleLevelStyle.messageColor(for: event.level))
                .textSelection(.enabled)
                .lineLimit(8)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if row.repeats > 1 {
                Text("×\(row.repeats)")
                    .font(EditorType.badge)
                    .foregroundColor(.editorTextSecondary)
                    .padding(.horizontal, 5)
                    .frame(minHeight: 16)
                    .background(Color.editorBadgeBackground)
                    .clipShape(Capsule())
                    .help("Repeated \(row.repeats) times in a row")
            }
            if source.isEmpty == false {
                Text(source)
                    .font(EditorType.monoSmall)
                    .foregroundColor(.editorTextTertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(minWidth: 80, idealWidth: 220, maxWidth: 220, alignment: .trailing)
                    .help("\(event.file):\(event.line)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ConsoleLevelStyle.rowBackground(for: event.level))
    }
}
