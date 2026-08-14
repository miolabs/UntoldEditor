//
//  EditorTheme.swift
//  UntoldEditor
//
//  Created by Javier Segura Perez on 4/10/25.
//  Based on: https://sebwhitfield.medium.com/building-a-code-editor-using-swiftui-bb74819b5c1f
//

import SwiftUI
import AppKit

struct SyntaxOption {
    var word: String
    var color: NSColor
    var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)
}

protocol Themeable {
    var syntaxOptions: [SyntaxOption] { get }
    var backgroundColor: NSColor { get }
}

struct EditorTheme: Identifiable, Themeable {
    var id = UUID()
    var name: String
    var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)
    
    var syntaxOptions: [SyntaxOption]
    var backgroundColor: NSColor = .textBackgroundColor
}
