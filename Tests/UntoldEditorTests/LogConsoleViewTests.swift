//
//  LogConsoleViewTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// These unit tests were jump-started with AI assistance — then refined by humans. If you spot an issue, please submit an issue.

@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

final class LogConsoleViewTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Ensure a clean LogStore before each test
        LogStore.shared.clear()
        // Wait for main-queue clear to complete
        let exp = expectation(description: "clear flush")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
    }

    override func tearDown() {
        LogStore.shared.clear()
        let exp = expectation(description: "clear flush")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
        super.tearDown()
    }

    private func makeEvent(level: LogLevel,
                           category: String,
                           message: String,
                           file: String = "SomeFile.swift",
                           function: String = "someFunc()",
                           line: Int = 42) -> LogEvent
    {
        LogEvent(level: level,
                 message: message,
                 file: file,
                 function: function,
                 line: line,
                 category: category)
    }

    func test_logStore_appendsAndTrims() {
        // Arrange
        let max = 5000
        let many = max + 25

        // Act
        for i in 0 ..< many {
            let e = makeEvent(level: .info, category: "General", message: "msg \(i)")
            LogStore.shared.didLog(e)
        }

        // didLog enqueues on main; wait for it.
        let exp = expectation(description: "didLog flush")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        // Assert
        XCTAssertEqual(LogStore.shared.entries.count, max, "Store should trim to \(max) entries.")
        XCTAssertTrue(LogStore.shared.entries.first?.message == "msg 25",
                      "Oldest entries should be trimmed first.")
        XCTAssertTrue(LogStore.shared.entries.last?.message == "msg \(many - 1)")
    }
}
