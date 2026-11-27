//
//  EditorPanelBadges.swift
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

/// The counts the tabs show as badges, per panel: today the console's errors
/// logged while it was off screen. A panel sets its count; a tab reads it.
final class EditorPanelBadges: ObservableObject {
    static let shared = EditorPanelBadges()

    @Published private(set) var counts: [PanelID: Int] = [:]

    func count(for panel: PanelID) -> Int {
        counts[panel] ?? 0
    }

    func set(_ count: Int, for panel: PanelID) {
        let value: Int? = count > 0 ? count : nil
        if counts[panel] != value {
            counts[panel] = value
        }
    }
}
