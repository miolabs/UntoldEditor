//
//  EditorInputViewHitTestTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

@testable import UntoldEditor
import UntoldEngine
import XCTest

#if canImport(AppKit)
    import AppKit

    /// The canvas must only receive scroll/mouse/key input when it is the
    /// frontmost view under the pointer. Views hosted in front of it (the
    /// project gallery, panels) have to win the hit test even though the
    /// pointer is still inside the canvas bounds.
    final class EditorInputViewHitTestTests: XCTestCase {
        private var window: NSWindow!
        private var canvas: NSView!

        override func setUp() {
            super.setUp()
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            // Programmatic windows release themselves on close(); under ARC
            // that double-frees, so keep ownership with the test instead.
            window.isReleasedWhenClosed = false
            canvas = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
            window.contentView?.addSubview(canvas)
        }

        override func tearDown() {
            window.close()
            window = nil
            canvas = nil
            super.tearDown()
        }

        func test_pointerOverUncoveredCanvas_isFrontmost() {
            XCTAssertTrue(InputSystem.isEditorInputViewFrontmost(at: NSPoint(x: 200, y: 150), in: canvas))
        }

        func test_pointerOverOverlayInFrontOfCanvas_isNotFrontmost() {
            // Overlay covers the left half of the canvas, like the gallery does.
            let overlay = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 300))
            window.contentView?.addSubview(overlay, positioned: .above, relativeTo: canvas)

            XCTAssertFalse(InputSystem.isEditorInputViewFrontmost(at: NSPoint(x: 100, y: 150), in: canvas))
            XCTAssertTrue(InputSystem.isEditorInputViewFrontmost(at: NSPoint(x: 300, y: 150), in: canvas))
        }

        func test_pointerOverCanvasSubview_isFrontmost() {
            let child = NSView(frame: NSRect(x: 10, y: 10, width: 50, height: 50))
            canvas.addSubview(child)

            XCTAssertTrue(InputSystem.isEditorInputViewFrontmost(at: NSPoint(x: 20, y: 20), in: canvas))
        }

        func test_pointerOutsideCanvas_isNotFrontmost() {
            XCTAssertFalse(InputSystem.isEditorInputViewFrontmost(at: NSPoint(x: -10, y: 150), in: canvas))
        }

        func test_hiddenCanvas_isNotFrontmost() {
            canvas.isHidden = true
            XCTAssertFalse(InputSystem.isEditorInputViewFrontmost(at: NSPoint(x: 200, y: 150), in: canvas))
        }

        func test_canvasWithoutWindow_isNotFrontmost() {
            let detached = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
            XCTAssertFalse(InputSystem.isEditorInputViewFrontmost(at: NSPoint(x: 50, y: 50), in: detached))
        }
    }
#endif
