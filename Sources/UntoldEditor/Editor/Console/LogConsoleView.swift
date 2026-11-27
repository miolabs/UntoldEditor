//
//  LogConsoleView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI
import UntoldEngine

/// The Console panel: the engine's log under a sub-bar of level chips and
/// switches, on the mockup's grid. The list follows new messages unless
/// Auto-scroll is off or an error stopped it; the panel tells the model when
/// it is on screen, so errors logged while it was not are the tab's badge.
struct LogConsoleView: View {
    @Binding var searchQuery: String
    @ObservedObject private var model = EditorConsoleModel.shared
    @ObservedObject private var store = LogStore.shared

    init(searchQuery: Binding<String>) {
        _searchQuery = searchQuery
    }

    var body: some View {
        let rows = ConsoleRow.rows(from: store.entries, filter: model.filter, query: searchQuery, collapsing: model.collapses)
        let counts = ConsoleCounts(store.entries)
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                ConsoleSubBar(model: model, counts: counts) {
                    model.resume()
                    if let last = rows.last?.id {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
                if rows.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { row in
                                ConsoleRowView(row: row)
                                    .id(row.id)
                            }
                        }
                    }
                    .onChange(of: rows.last?.id) { _, last in
                        if model.follows, let last {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.editorPanelBackground)
        .onAppear {
            model.isVisible = true
        }
        .onDisappear {
            model.isVisible = false
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 22))
                .foregroundColor(.editorTextTertiary)
            Text(emptyText)
                .font(EditorType.body)
                .foregroundColor(.editorTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyText: String {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty == false {
            return "No messages match “\(query)”"
        }
        switch model.filter {
        case .all: return "No messages"
        case .errors: return "No errors"
        case .warnings: return "No warnings"
        case .info: return "No information messages"
        }
    }
}
