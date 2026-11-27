//
//  ConsoleRow.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Foundation
import UntoldEngine

/// A row of the console: a message, folded with the identical messages that
/// followed it when the console collapses repeats.
struct ConsoleRow: Identifiable {
    let event: LogEvent
    /// How many consecutive identical messages the row stands for; 1 when it
    /// stands for its own message alone.
    let repeats: Int

    var id: UUID {
        event.id
    }

    /// The rows for the messages that pass the chip and the filter field, in
    /// order, folded when `collapsing`: a message identical to the one shown
    /// before it joins that row instead of taking one of its own.
    static func rows(from events: [LogEvent], filter: ConsoleLevelFilter, query: String, collapsing: Bool) -> [ConsoleRow] {
        var rows: [ConsoleRow] = []
        for event in events where filter.matches(event.level) && matches(event, query: query) {
            if collapsing, let last = rows.last, isRepeat(event, of: last.event) {
                rows[rows.count - 1] = ConsoleRow(event: last.event, repeats: last.repeats + 1)
            } else {
                rows.append(ConsoleRow(event: event, repeats: 1))
            }
        }
        return rows
    }

    /// The filter field matches the message or the category, whatever the case.
    static func matches(_ event: LogEvent, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty
            || event.message.localizedCaseInsensitiveContains(query)
            || event.category.localizedCaseInsensitiveContains(query)
    }

    /// Two messages fold when they say the same at the same level.
    static func isRepeat(_ event: LogEvent, of other: LogEvent) -> Bool {
        event.level == other.level && event.message == other.message
    }
}
