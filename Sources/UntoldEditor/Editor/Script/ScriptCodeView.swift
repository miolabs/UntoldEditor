//
//  CodeView.swift
//  UntoldEditor
//
//  Created by Javier Segura Perez on 4/10/25.
//

import SwiftUI
import AppKit

struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var theme: EditorTheme
    var padding: CGFloat = 12
    
    @State var textView: NSTextView?
    
    func makeNSView(context: Context) -> NSView {
        let view = NSTextView.scrollableTextView()
        guard let textView = view.documentView as? NSTextView else { return view }
        
        DispatchQueue.main.asyncAfter(deadline: .now()) {
            self.textView = textView
            configureTextView(with: context)
        }
        
        view.contentInsets = .init(top: padding, left: padding, bottom: padding, right: padding)
        view.automaticallyAdjustsContentInsets = false
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) { }
    
    func configureTextView(with context: Context) {
        textView?.font = theme.font
        textView?.isEditable = true
        textView?.isRichText = false
        textView?.backgroundColor = theme.backgroundColor
    }
}


