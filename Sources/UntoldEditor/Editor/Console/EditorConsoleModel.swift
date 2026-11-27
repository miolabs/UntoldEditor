//
//  EditorConsoleModel.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Combine
import Foundation
import UntoldEngine

/// What the console remembers and decides beyond the messages themselves: the
/// level its chips show, whether repeats fold, whether following stops at an
/// error, whether the list follows new messages at all, and the errors logged
/// while the console was not on screen, which its tab shows as a badge. The
/// three switches persist. Pure Swift: the view reads it, and the layout's
/// tabs read the badge through `EditorPanelBadges`.
final class EditorConsoleModel: ObservableObject {
    static let shared = EditorConsoleModel(defaults: .standard, store: LogStore.shared, badges: .shared)

    static let collapsesKey = "editor.console.collapses"
    static let pausesOnErrorKey = "editor.console.pausesOnError"
    static let autoScrollsKey = "editor.console.autoScrolls"

    /// The chip in front.
    @Published var filter: ConsoleLevelFilter = .all
    /// Whether consecutive identical messages fold into one row.
    @Published var collapses: Bool {
        didSet { defaults?.set(collapses, forKey: Self.collapsesKey) }
    }

    /// Whether following stops at the first error, until resumed.
    @Published var pausesOnError: Bool {
        didSet {
            defaults?.set(pausesOnError, forKey: Self.pausesOnErrorKey)
            if pausesOnError == false {
                isPausedByError = false
            }
        }
    }

    /// Whether the list follows new messages.
    @Published var autoScrolls: Bool {
        didSet {
            defaults?.set(autoScrolls, forKey: Self.autoScrollsKey)
            if autoScrolls == false {
                isPausedByError = false
            }
        }
    }

    /// Following stopped at an error; `resume` starts it again.
    @Published private(set) var isPausedByError = false
    /// The errors logged while the console was not on screen.
    @Published private(set) var unreadErrors = 0 {
        didSet { badges?.set(unreadErrors, for: .console) }
    }

    /// Whether the console is on screen, set by its view. An error logged
    /// while it is on screen is seen at once; showing it clears the badge.
    var isVisible = false {
        didSet {
            if isVisible {
                markSeen()
            }
        }
    }

    private let defaults: UserDefaults?
    private let store: LogStore?
    private let badges: EditorPanelBadges?
    private var lastProcessedID: UUID?
    private var subscription: AnyCancellable?

    /// Reads the switches from `defaults` and follows `store`'s messages;
    /// pass nil for a model that is fed by `take` and persists nothing.
    init(defaults: UserDefaults?, store: LogStore?, badges: EditorPanelBadges?) {
        self.defaults = defaults
        self.store = store
        self.badges = badges
        collapses = defaults?.object(forKey: Self.collapsesKey) as? Bool ?? false
        pausesOnError = defaults?.object(forKey: Self.pausesOnErrorKey) as? Bool ?? false
        autoScrolls = defaults?.object(forKey: Self.autoScrollsKey) as? Bool ?? true
        subscription = store?.$entries.sink { [weak self] entries in
            self?.take(entries)
        }
    }

    convenience init() {
        self.init(defaults: nil, store: nil, badges: nil)
    }

    /// Whether the list should follow new messages now.
    var follows: Bool {
        autoScrolls && isPausedByError == false
    }

    /// The store's messages as they stand. The ones after the last message
    /// seen here are new: an error among them counts as unread while the
    /// console is off screen, and stops following when that is asked for.
    func take(_ entries: [LogEvent]) {
        let fresh = newEvents(in: entries)
        lastProcessedID = entries.last?.id
        for event in fresh where event.level == .error {
            if isVisible == false {
                unreadErrors += 1
            }
            if pausesOnError, autoScrolls, isPausedByError == false {
                isPausedByError = true
            }
        }
    }

    /// The badge is cleared: the console has been looked at.
    func markSeen() {
        if unreadErrors != 0 {
            unreadErrors = 0
        }
    }

    /// Follows new messages again after an error stopped it.
    func resume() {
        isPausedByError = false
    }

    /// Removes every message; nothing is left unread or paused.
    func clear() {
        store?.clear()
        lastProcessedID = nil
        isPausedByError = false
        markSeen()
    }

    private func newEvents(in entries: [LogEvent]) -> ArraySlice<LogEvent> {
        guard let lastProcessedID else { return entries[...] }
        if let index = entries.lastIndex(where: { $0.id == lastProcessedID }) {
            return entries[(index + 1)...]
        }
        // Cleared, or trimmed past the last one seen: all of it is new.
        return entries[...]
    }
}
