//
//  EditorConsoleModelTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

/// The console's rules without its view: the chips and the filter field, the
/// folding of repeats, the unread badge, following and its pause at an error,
/// and the switches that persist.
final class EditorConsoleModelTests: XCTestCase {
    private func event(_ level: LogLevel, _ message: String, category: String = "General", file: String = "/Sources/Some/File.swift", line: Int = 42) -> LogEvent {
        LogEvent(level: level, message: message, file: file, function: "f()", line: line, category: category)
    }

    private var sample: [LogEvent] {
        [
            event(.info, "Scene loaded"),
            event(.warning, "Texture is large", category: "AssetImporter"),
            event(.error, "Shader compile failed", category: "Renderer"),
            event(.error, "Shader compile failed", category: "Renderer"),
            event(.debug, "Draw call 42", category: "Renderer"),
            event(.error, "Shader compile failed", category: "Renderer"),
            event(.test, "Injected"),
        ]
    }

    // MARK: - Chips and the filter field

    func test_counts_putEverythingThatIsNotAnErrorOrAWarningUnderInfo() {
        let counts = ConsoleCounts(sample)
        XCTAssertEqual(counts, ConsoleCounts(all: 7, errors: 3, warnings: 1, info: 3))
        XCTAssertEqual(counts.count(for: .all), 7)
        XCTAssertEqual(counts.count(for: .errors), 3)
        XCTAssertEqual(counts.count(for: .warnings), 1)
        XCTAssertEqual(counts.count(for: .info), 3)
    }

    func test_chipLabels_carryTheirCount() {
        XCTAssertEqual(ConsoleLevelFilter.all.label(count: 14), "All 14")
        XCTAssertEqual(ConsoleLevelFilter.errors.label(count: 2), "2 errors")
        XCTAssertEqual(ConsoleLevelFilter.errors.label(count: 1), "1 error")
        XCTAssertEqual(ConsoleLevelFilter.warnings.label(count: 3), "3 warnings")
        XCTAssertEqual(ConsoleLevelFilter.warnings.label(count: 1), "1 warning")
        XCTAssertEqual(ConsoleLevelFilter.info.label(count: 9), "9 info")
    }

    func test_chips_filterByLevel() {
        let events = sample
        XCTAssertEqual(ConsoleRow.rows(from: events, filter: .all, query: "", collapsing: false).count, 7)
        XCTAssertEqual(ConsoleRow.rows(from: events, filter: .errors, query: "", collapsing: false).count, 3)
        XCTAssertEqual(ConsoleRow.rows(from: events, filter: .warnings, query: "", collapsing: false).map(\.event.message), ["Texture is large"])
        XCTAssertEqual(
            ConsoleRow.rows(from: events, filter: .info, query: "", collapsing: false).map(\.event.message),
            ["Scene loaded", "Draw call 42", "Injected"]
        )
    }

    func test_theFilterField_matchesTheMessageOrTheCategory_whateverTheCase() {
        let events = sample
        XCTAssertEqual(ConsoleRow.rows(from: events, filter: .all, query: "draw", collapsing: false).map(\.event.message), ["Draw call 42"])
        XCTAssertEqual(ConsoleRow.rows(from: events, filter: .all, query: "RENDERER", collapsing: false).count, 4)
        XCTAssertEqual(ConsoleRow.rows(from: events, filter: .info, query: "renderer", collapsing: false).map(\.event.message), ["Draw call 42"])
        XCTAssertEqual(ConsoleRow.rows(from: events, filter: .all, query: "  ", collapsing: false).count, 7, "Blank is no filter")
        XCTAssertTrue(ConsoleRow.rows(from: events, filter: .all, query: "nothing like it", collapsing: false).isEmpty)
    }

    // MARK: - Collapse

    func test_collapse_foldsConsecutiveIdenticalMessages_only() {
        let events = sample
        let rows = ConsoleRow.rows(from: events, filter: .all, query: "", collapsing: true)

        XCTAssertEqual(rows.map(\.event.message), ["Scene loaded", "Texture is large", "Shader compile failed", "Draw call 42", "Shader compile failed", "Injected"])
        XCTAssertEqual(rows.map(\.repeats), [1, 1, 2, 1, 1, 1])
        XCTAssertEqual(rows[2].id, events[2].id, "The row keeps the first of the repeats")
    }

    func test_collapse_foldsWhatIsShownNextToEachOther() {
        let rows = ConsoleRow.rows(from: sample, filter: .errors, query: "", collapsing: true)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.repeats, 3, "With the debug line hidden, the three errors are consecutive")
    }

    func test_collapse_keepsDifferentLevelsApart() {
        let events = [event(.warning, "Same words"), event(.error, "Same words")]
        XCTAssertEqual(ConsoleRow.rows(from: events, filter: .all, query: "", collapsing: true).count, 2)
    }

    func test_collapseOff_givesEveryMessageItsRow() {
        XCTAssertEqual(ConsoleRow.rows(from: sample, filter: .all, query: "", collapsing: false).map(\.repeats), Array(repeating: 1, count: 7))
    }

    // MARK: - Unread badge

    func test_errorsLoggedWhileOffScreen_areUnread_untilTheConsoleShows() {
        let badges = EditorPanelBadges()
        let model = EditorConsoleModel(defaults: nil, store: nil, badges: badges)
        model.isVisible = false

        var entries = [event(.info, "a"), event(.error, "b")]
        model.take(entries)
        XCTAssertEqual(model.unreadErrors, 1)
        XCTAssertEqual(badges.count(for: .console), 1)

        entries.append(event(.warning, "c"))
        entries.append(event(.error, "d"))
        model.take(entries)
        XCTAssertEqual(model.unreadErrors, 2, "Only what arrived since the last look counts, and warnings do not")

        model.isVisible = true
        XCTAssertEqual(model.unreadErrors, 0)
        XCTAssertEqual(badges.count(for: .console), 0)

        entries.append(event(.error, "e"))
        model.take(entries)
        XCTAssertEqual(model.unreadErrors, 0, "Seen at once while on screen")

        model.isVisible = false
        entries.append(event(.error, "f"))
        model.take(entries)
        XCTAssertEqual(model.unreadErrors, 1)
    }

    func test_take_countsEveryMessageOnceAcrossRepeatedHandOvers() {
        let model = EditorConsoleModel()
        let entries = [event(.error, "a"), event(.error, "b")]
        model.take(entries)
        model.take(entries)
        XCTAssertEqual(model.unreadErrors, 2)
    }

    func test_take_afterTheStoreWasEmptied_startsOver() {
        let model = EditorConsoleModel()
        model.take([event(.error, "a")])
        model.take([])
        model.take([event(.error, "b")])
        XCTAssertEqual(model.unreadErrors, 2)
    }

    func test_markSeen_clearsTheBadge() {
        let badges = EditorPanelBadges()
        let model = EditorConsoleModel(defaults: nil, store: nil, badges: badges)
        model.take([event(.error, "a")])
        model.markSeen()
        XCTAssertEqual(model.unreadErrors, 0)
        XCTAssertEqual(badges.counts[.console], nil)
    }

    // MARK: - Following and the pause at an error

    func test_pauseOnError_stopsFollowingAtTheFirstError_untilResumed() {
        let model = EditorConsoleModel()
        model.pausesOnError = true
        XCTAssertTrue(model.follows)

        var entries = [event(.warning, "a")]
        model.take(entries)
        XCTAssertFalse(model.isPausedByError, "A warning does not stop it")

        entries.append(event(.error, "b"))
        model.take(entries)
        XCTAssertTrue(model.isPausedByError)
        XCTAssertFalse(model.follows)

        entries.append(event(.error, "c"))
        model.take(entries)
        XCTAssertTrue(model.isPausedByError, "Stays stopped through further errors")

        model.resume()
        XCTAssertFalse(model.isPausedByError)
        XCTAssertTrue(model.follows)

        entries.append(event(.error, "d"))
        model.take(entries)
        XCTAssertTrue(model.isPausedByError, "The next error stops it again")
    }

    func test_pauseOnError_doesNothingWhenOff_orWhenNotFollowing() {
        let off = EditorConsoleModel()
        off.take([event(.error, "a")])
        XCTAssertFalse(off.isPausedByError)

        let notFollowing = EditorConsoleModel()
        notFollowing.pausesOnError = true
        notFollowing.autoScrolls = false
        notFollowing.take([event(.error, "a")])
        XCTAssertFalse(notFollowing.isPausedByError)
        XCTAssertFalse(notFollowing.follows)
    }

    func test_turningASwitchOff_liftsThePause() {
        let model = EditorConsoleModel()
        model.pausesOnError = true
        model.take([event(.error, "a")])
        XCTAssertTrue(model.isPausedByError)

        model.autoScrolls = false
        XCTAssertFalse(model.isPausedByError)

        model.autoScrolls = true
        model.take([event(.error, "a"), event(.error, "b")])
        XCTAssertTrue(model.isPausedByError)
        model.pausesOnError = false
        XCTAssertFalse(model.isPausedByError)
        XCTAssertTrue(model.follows)
    }

    func test_clear_leavesNothingUnreadOrPaused() {
        let model = EditorConsoleModel()
        model.pausesOnError = true
        model.take([event(.error, "a")])

        model.clear()

        XCTAssertEqual(model.unreadErrors, 0)
        XCTAssertFalse(model.isPausedByError)
        model.take([event(.error, "b")])
        XCTAssertEqual(model.unreadErrors, 1, "What arrives after the clear counts again")
    }

    // MARK: - Persistence

    func test_theSwitchesSurviveARelaunch_andStartAsTheMockupHasThem() throws {
        let suiteName = "EditorConsoleModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = EditorConsoleModel(defaults: defaults, store: nil, badges: nil)
        XCTAssertFalse(first.collapses)
        XCTAssertFalse(first.pausesOnError)
        XCTAssertTrue(first.autoScrolls)
        first.collapses = true
        first.pausesOnError = true
        first.autoScrolls = false

        let second = EditorConsoleModel(defaults: defaults, store: nil, badges: nil)
        XCTAssertTrue(second.collapses)
        XCTAssertTrue(second.pausesOnError)
        XCTAssertFalse(second.autoScrolls)
        XCTAssertEqual(second.filter, .all, "The chip in front is not remembered")
    }

    // MARK: - The row's texts

    func test_source_isTheFileNameAndLine_orNothing() {
        XCTAssertEqual(ConsoleLevelStyle.source(file: "/Users/me/Sources/Renderer/ShaderCompiler.swift", line: 157), "ShaderCompiler.swift:157")
        XCTAssertEqual(ConsoleLevelStyle.source(file: "", line: 3), "")
    }

    func test_badges_keepOnlyCountsAbove_zero() {
        let badges = EditorPanelBadges()
        badges.set(3, for: .console)
        XCTAssertEqual(badges.count(for: .console), 3)
        badges.set(0, for: .console)
        XCTAssertEqual(badges.count(for: .console), 0)
        XCTAssertTrue(badges.counts.isEmpty)
        XCTAssertEqual(badges.count(for: .tasks), 0)
    }
}
