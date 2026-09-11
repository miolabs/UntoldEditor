//
//  SplatDebugMenuTests.swift
//  UntoldEditorTests
//
//  View > Splat Debug: every engine switch (GaussianDebugOptions) the menu exposes round-trips
//  through its menu option, the level mode through its radio items, and the items are
//  distinct and grouped in menu order.
//

@testable import UntoldEditor
import UntoldEngine
import XCTest

final class SplatDebugMenuTests: XCTestCase {
    private var savedSwitches: [SplatDebugOption: Bool] = [:]
    private var savedLevelMode = GaussianLevelMode.auto

    override func setUp() {
        super.setUp()
        for option in SplatDebugOption.allCases {
            savedSwitches[option] = option.isEnabled
        }
        savedLevelMode = GaussianDebugOptions.shared.gaussianLevelMode
    }

    override func tearDown() {
        for (option, value) in savedSwitches {
            option.isEnabled = value
        }
        GaussianDebugOptions.shared.gaussianLevelMode = savedLevelMode
        super.tearDown()
    }

    func test_everySwitchRoundTripsToTheEngine() {
        let options = GaussianDebugOptions.shared
        for option in SplatDebugOption.allCases {
            option.isEnabled = true
            XCTAssertTrue(option.isEnabled, option.title)
            option.isEnabled = false
            XCTAssertFalse(option.isEnabled, option.title)
        }
        // Each option drives its own engine switch, not a neighbour's.
        SplatDebugOption.paging.isEnabled = true
        XCTAssertTrue(options.disablePaging)
        XCTAssertFalse(options.freezePaging)
        SplatDebugOption.paging.isEnabled = false
        SplatDebugOption.freezePaging.isEnabled = true
        XCTAssertTrue(options.freezePaging)
        XCTAssertFalse(options.disablePaging)
        SplatDebugOption.freezePaging.isEnabled = false
        SplatDebugOption.residencyTint.isEnabled = true
        XCTAssertTrue(options.residencyDebugTint)
        SplatDebugOption.residencyTint.isEnabled = false
        SplatDebugOption.levelCrossFade.isEnabled = true
        XCTAssertTrue(options.disableLevelCrossFade)
        XCTAssertFalse(options.levelDebugTint)
        SplatDebugOption.levelCrossFade.isEnabled = false
        SplatDebugOption.levelTint.isEnabled = true
        XCTAssertTrue(options.levelDebugTint)
        SplatDebugOption.levelTint.isEnabled = false
        SplatDebugOption.chunkCull.isEnabled = true
        XCTAssertTrue(options.disableChunkCull)
        SplatDebugOption.chunkCull.isEnabled = false
        SplatDebugOption.workingSetBudget.isEnabled = true
        XCTAssertTrue(options.disableWorkingSetBudget)
        SplatDebugOption.workingSetBudget.isEnabled = false
        SplatDebugOption.screenWeightedQuotas.isEnabled = true
        XCTAssertTrue(options.disableScreenWeightedQuotas)
        SplatDebugOption.screenWeightedQuotas.isEnabled = false
    }

    func test_itemsAreDistinctAndGroupedInMenuOrder() {
        let titles = SplatDebugOption.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count, "every item has its own title")
        for option in SplatDebugOption.allCases {
            XCTAssertFalse(option.summary.isEmpty, option.title)
            XCTAssertTrue(option.title.contains("Splat"), option.title)
        }
        let groups = SplatDebugOption.allCases.map(\.group.rawValue)
        XCTAssertEqual(groups, groups.sorted(), "the groups are contiguous in menu order")
        XCTAssertEqual(SplatDebugOption.allCases.filter { $0.group == .paging }, [.paging, .freezePaging, .residencyTint])
        XCTAssertEqual(SplatDebugOption.allCases.filter { $0.group == .levels }, [.levelCrossFade, .levelTint])
        XCTAssertEqual(SplatDebugOption.paging.title, "Disable Splat Paging")
        XCTAssertEqual(SplatDebugOption.levelTint.title, "Tint Splats by Level")
        XCTAssertEqual(SplatDebugOption.levelCrossFade.title, "Disable Splat Level Cross-Fade")
    }

    func test_levelModeRoundTripsThroughItsRadioItems() {
        XCTAssertEqual(SplatLevelModeOption.allCases.map(\.title), ["Auto", "Fine Only", "Coarse Only"])
        for mode in SplatLevelModeOption.allCases {
            SplatLevelModeOption.current = mode
            XCTAssertEqual(GaussianDebugOptions.shared.gaussianLevelMode, mode.mode, mode.title)
            XCTAssertEqual(SplatLevelModeOption.current, mode)
            XCTAssertFalse(mode.summary.isEmpty)
        }
        GaussianDebugOptions.shared.gaussianLevelMode = .coarseOnly
        XCTAssertEqual(SplatLevelModeOption.current, .coarseOnly, "a mode set by the engine shows in the menu")
        for mode in GaussianLevelMode.allCases {
            XCTAssertEqual(SplatLevelModeOption(mode: mode).mode, mode)
        }
    }
}
