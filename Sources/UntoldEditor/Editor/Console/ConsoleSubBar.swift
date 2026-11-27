//
//  ConsoleSubBar.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The row under the console's tab strip, from the mockup: the level chips
/// with their counts on the left; on the right Clear, the Collapse, Pause on
/// error and Auto-scroll switches, and Resume while following has stopped at
/// an error. Where the row is too narrow for both sides it scrolls sideways.
struct ConsoleSubBar: View {
    @ObservedObject var model: EditorConsoleModel
    let counts: ConsoleCounts
    /// Follows new messages again, and jumps to the latest one.
    let onResume: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                chips
                Spacer(minLength: 8)
                controls
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    chips
                    controls
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(Color.editorPanelBackground)
        .overlay(alignment: .bottom) {
            Color.editorHairline
                .frame(height: 1)
        }
    }

    private var chips: some View {
        ForEach(ConsoleLevelFilter.allCases) { filter in
            EditorFilterChip(
                label: filter.label(count: counts.count(for: filter)),
                systemImage: filter.systemImage,
                tint: Self.tint(for: filter),
                isActive: model.filter == filter
            ) {
                model.filter = filter
            }
            .help(filter.help)
        }
    }

    private var controls: some View {
        HStack(spacing: 4) {
            if model.isPausedByError {
                EditorFilterChip(label: "Resume", systemImage: "play.fill", tint: .editorAccent, action: onResume)
                    .help("Follow new messages again")
            }
            EditorFilterChip(label: "Clear") {
                model.clear()
            }
            .help("Remove every message")
            EditorFilterChip(label: "Collapse", isActive: model.collapses) {
                model.collapses.toggle()
            }
            .help("Fold repeated messages into one row")
            EditorFilterChip(label: "Pause on error", isActive: model.pausesOnError) {
                model.pausesOnError.toggle()
            }
            .help("Stop following new messages at the first error")
            EditorFilterChip(label: "Auto-scroll", isActive: model.autoScrolls) {
                model.autoScrolls.toggle()
            }
            .help("Follow new messages as they arrive")
        }
    }

    /// The chip's colour when it is not in front: the level's own for errors
    /// and warnings.
    static func tint(for filter: ConsoleLevelFilter) -> Color {
        switch filter {
        case .errors: return .editorError
        case .warnings: return .editorWarning
        case .all, .info: return .editorTextSecondary
        }
    }
}
