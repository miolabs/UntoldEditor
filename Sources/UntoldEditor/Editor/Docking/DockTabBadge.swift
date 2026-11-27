//
//  DockTabBadge.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The red count on a tab: the errors the console logged while it was not on
/// screen.
struct DockTabBadge: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(EditorType.badge)
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 16, minHeight: 16)
            .background(Color.editorBadge)
            .clipShape(Capsule())
            .accessibilityLabel(count == 1 ? "1 unread error" : "\(count) unread errors")
    }
}
