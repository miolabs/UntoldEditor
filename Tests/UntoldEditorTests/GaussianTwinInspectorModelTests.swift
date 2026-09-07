//
//  GaussianTwinInspectorModelTests.swift
//  UntoldEditorTests
//
//  The Splat Twin section's model: assign / remove write at once, field edits apply live and
//  persist after a pause, every change is undoable, errors surface as status text.
//

import Foundation
@testable import UntoldEditor
@testable import UntoldEngine
import UntoldGaussianTwins
import XCTest

final class GaussianTwinInspectorModelTests: XCTestCase {
    private var directory: URL!
    private var untold: URL!
    private var payload: URL!
    private var entity: EntityID = .invalid
    private var undoManager: EditorUndoManager!
    /// Actions handed to the injected scheduler, oldest first, with their delay.
    private var scheduled: [(delay: TimeInterval, action: () -> Void)] = []
    private var cancelledCount = 0

    override func setUpWithError() throws {
        try super.setUpWithError()
        scene = Scene()
        directory = try GaussianTwinTestFixtures.makeTemporaryDirectory()
        untold = try GaussianTwinTestFixtures.writeUntold(to: directory)
        payload = try GaussianTwinTestFixtures.writeUntoldGS(to: directory.appendingPathComponent("Chair.untoldgs"), splatCount: 4)
        entity = GaussianTwinTestFixtures.makeMeshEntity(assetURL: untold)
        undoManager = EditorUndoManager()
        scheduled = []
        cancelledCount = 0
    }

    override func tearDown() {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        directory = nil
        undoManager = nil
        super.tearDown()
    }

    private func makeModel(entityId: EntityID? = nil) -> GaussianTwinInspectorModel {
        GaussianTwinInspectorModel(
            entityId: entityId ?? entity,
            scheduler: { [unowned self] delay, action in
                scheduled.append((delay, action))
                return { [unowned self] in cancelledCount += 1 }
            },
            undoManager: undoManager
        )
    }

    private func storedLink() throws -> UntoldAssetPatcher.GaussianAssetLink? {
        try UntoldAssetPatcher.gaussianAssets(in: Data(contentsOf: untold))[0]
    }

    // MARK: - Assign / remove

    func test_freshModel_resolvesTargetAndShowsNoTwin() {
        let model = makeModel()
        XCTAssertEqual(model.target, GaussianTwinLinkTarget(untoldURL: untold.standardizedFileURL, entityRecordId: 0))
        XCTAssertNil(model.link)
        XCTAssertEqual(model.payloadDisplay, GaussianTwinInspectorModel.noTwinTitle)
        XCTAssertNil(model.status)
        XCTAssertFalse(model.hasPendingPersist)
    }

    func test_assign_writesAtOnceAndRegistersUndo() throws {
        let model = makeModel()
        model.assign(payloadURL: payload)

        XCTAssertEqual(model.link?.payloadPath, "Chair.untoldgs")
        XCTAssertEqual(model.link?.lodSplatCounts, [4])
        XCTAssertEqual(model.payloadDisplay, "Chair.untoldgs")
        XCTAssertEqual(try storedLink(), model.link, "assign persists immediately")
        XCTAssertTrue(scheduled.isEmpty, "no debounce for assign")
        XCTAssertEqual(model.status?.isError, false)
        XCTAssertTrue(model.status?.message.contains("4 splats") == true, model.status?.message ?? "")
        XCTAssertNotNil(scene.get(component: GaussianAssetLinkComponent.self, for: entity))
        XCTAssertTrue(undoManager.canUndo)

        undoManager.undo()
        XCTAssertNil(try storedLink(), "undo removes the record from the file")
        XCTAssertNil(model.link, "the model follows the file")
        XCTAssertNil(scene.get(component: GaussianAssetLinkComponent.self, for: entity))

        undoManager.redo()
        XCTAssertEqual(try storedLink()?.payloadPath, "Chair.untoldgs")
        XCTAssertEqual(model.link?.payloadPath, "Chair.untoldgs")
    }

    func test_assign_keepsTheSettingsOfTheReplacedLink() throws {
        let model = makeModel()
        model.assign(payloadURL: payload)
        model.setSwapDistance(6)
        model.flushPendingPersist()

        let other = try GaussianTwinTestFixtures.writeUntoldGS(to: directory.appendingPathComponent("Chair_v2.untoldgs"), splatCount: 9)
        model.assign(payloadURL: other)
        XCTAssertEqual(model.link?.payloadPath, "Chair_v2.untoldgs")
        XCTAssertEqual(model.link?.swapDistanceMeters, 6)
        XCTAssertEqual(model.link?.lodSplatCounts, [9])
        XCTAssertEqual(try storedLink(), model.link)
    }

    func test_assignSelectedAsset_acceptsOnlyCookedGaussians() {
        let model = makeModel()
        model.assignSelectedAsset(Asset(name: "Chair", category: AssetCategory.models.rawValue, path: untold))
        XCTAssertNil(model.link)
        XCTAssertEqual(model.status?.isError, true)

        model.assignSelectedAsset(Asset(name: "capture", category: AssetCategory.gaussians.rawValue, path: directory.appendingPathComponent("capture.ply")))
        XCTAssertNil(model.link, ".ply must be cooked first")

        model.assignSelectedAsset(Asset(name: "Chair", category: AssetCategory.gaussians.rawValue, path: payload))
        XCTAssertEqual(model.link?.payloadPath, "Chair.untoldgs")
    }

    func test_remove_writesAtOnceAndIsUndoable() throws {
        let model = makeModel()
        model.assign(payloadURL: payload)
        let linked = model.link

        model.removeLink()
        XCTAssertNil(model.link)
        XCTAssertNil(try storedLink())
        XCTAssertEqual(model.payloadDisplay, GaussianTwinInspectorModel.noTwinTitle)

        undoManager.undo()
        XCTAssertEqual(model.link, linked)
        XCTAssertEqual(try storedLink(), linked)
    }

    // MARK: - Fields

    func test_fieldEdit_appliesLiveAndPersistsAfterTheDebounce() throws {
        let model = makeModel()
        model.assign(payloadURL: payload)

        model.setSwapDistance(5)
        XCTAssertEqual(model.link?.swapDistanceMeters, 5)
        XCTAssertEqual(scene.get(component: GaussianAssetLinkComponent.self, for: entity)?.swapDistanceMeters, 5, "live on the scene")
        XCTAssertEqual(try storedLink()?.swapDistanceMeters, 0, "not on disk yet")
        XCTAssertTrue(model.hasPendingPersist)
        XCTAssertEqual(scheduled.count, 1)
        XCTAssertEqual(scheduled[0].delay, GaussianTwinInspectorModel.persistDelay)
        XCTAssertEqual(scheduled[0].delay, 0.4, accuracy: 0.0001)

        model.setOccluderShrink(0.05)
        XCTAssertEqual(cancelledCount, 1, "a second edit restarts the timer")
        XCTAssertEqual(scheduled.count, 2)
        XCTAssertEqual(try storedLink()?.swapDistanceMeters, 0)

        scheduled.last?.action()
        XCTAssertFalse(model.hasPendingPersist)
        XCTAssertEqual(try storedLink()?.swapDistanceMeters, 5)
        XCTAssertEqual(try storedLink()?.occluderShrinkMeters, 0.05)

        // Each edit is one undo step carrying the whole link.
        undoManager.undo()
        XCTAssertEqual(model.link?.occluderShrinkMeters, 0.02)
        XCTAssertEqual(model.link?.swapDistanceMeters, 5)
        XCTAssertEqual(try storedLink()?.occluderShrinkMeters, 0.02, "undo writes through")
        undoManager.undo()
        XCTAssertEqual(model.link?.swapDistanceMeters, 0)
        undoManager.undo()
        XCTAssertNil(model.link, "back to the unassigned asset")
        XCTAssertFalse(undoManager.canUndo)
    }

    func test_flushPendingPersist_writesNowAndCancelsTheTimer() throws {
        let model = makeModel()
        model.assign(payloadURL: payload)
        model.setExposureOffset(-1.5)
        XCTAssertTrue(model.hasPendingPersist)

        model.flushPendingPersist()
        XCTAssertFalse(model.hasPendingPersist)
        XCTAssertEqual(cancelledCount, 1)
        XCTAssertEqual(try storedLink()?.exposureOffsetEV, -1.5)

        scheduled.last?.action()
        XCTAssertEqual(try storedLink()?.exposureOffsetEV, -1.5, "a late timer is a no-op")
    }

    func test_undoDuringAPendingEdit_dropsThePendingWrite() throws {
        let model = makeModel()
        model.assign(payloadURL: payload)
        model.setSwapDistance(7)
        XCTAssertTrue(model.hasPendingPersist)

        undoManager.undo()
        XCTAssertEqual(model.link?.swapDistanceMeters, 0)
        XCTAssertFalse(model.hasPendingPersist, "the file now says what the undo wrote")
        scheduled.last?.action()
        XCTAssertEqual(try storedLink()?.swapDistanceMeters, 0)
    }

    func test_fieldValues_areClampedToTheirRanges() {
        let model = makeModel()
        model.assign(payloadURL: payload)

        model.setSwapDistance(-3)
        XCTAssertEqual(model.link?.swapDistanceMeters, 0)
        model.setOccluderShrink(-1)
        XCTAssertEqual(model.link?.occluderShrinkMeters, 0)
        model.setExposureOffset(9)
        XCTAssertEqual(model.link?.exposureOffsetEV, 4)
        model.setExposureOffset(-9)
        XCTAssertEqual(model.link?.exposureOffsetEV, -4)
        model.setExposureOffset(.nan)
        XCTAssertEqual(model.link?.exposureOffsetEV, -4, "non-finite input keeps the value")

        XCTAssertEqual(GaussianTwinInspector.clampedSwapDistance(2.5, previous: 0), 2.5)
        XCTAssertEqual(GaussianTwinInspector.clampedExposureOffset(.infinity, previous: 1), 1)
    }

    func test_fieldEdit_withoutALinkIsIgnored() {
        let model = makeModel()
        model.setSwapDistance(3)
        XCTAssertNil(model.link)
        XCTAssertFalse(model.hasPendingPersist)
        XCTAssertFalse(undoManager.canUndo)
    }

    // MARK: - Errors

    func test_assign_nonV3Payload_showsErrorAndChangesNothing() throws {
        let model = makeModel()
        model.assign(payloadURL: payload)
        let stale = try GaussianTwinTestFixtures.writeStalePayload(to: directory.appendingPathComponent("stale.untoldgs"))
        undoManager.clear()

        model.assign(payloadURL: stale)
        XCTAssertEqual(model.status?.isError, true)
        XCTAssertTrue(model.status?.message.contains("stale.untoldgs is not a usable .untoldgs payload") == true, model.status?.message ?? "")
        XCTAssertEqual(model.link?.payloadPath, "Chair.untoldgs", "the previous link stays")
        XCTAssertEqual(try storedLink()?.payloadPath, "Chair.untoldgs")
        XCTAssertFalse(undoManager.canUndo, "a failed assign registers no undo step")
    }

    func test_entityWithoutARecord_reportsTheFileInTheStatus() throws {
        let hierarchy = try GaussianTwinTestFixtures.writeUntold(to: directory, name: "Table", hierarchy: true)
        let placed = GaussianTwinTestFixtures.makeAssetInstance(assetURL: hierarchy, nodePath: "Root/root_entity#0/gone#5")

        let model = makeModel(entityId: placed.node)
        XCTAssertNil(model.target)
        XCTAssertEqual(model.status?.isError, true)
        XCTAssertTrue(model.status?.message.contains("Table.untold") == true, model.status?.message ?? "")
        model.assign(payloadURL: payload)
        XCTAssertNil(model.link)
    }

    // MARK: - Preview line

    func test_liveTwinDescription_reportsTheTwinState() throws {
        let model = makeModel()
        XCTAssertNil(model.liveTwinDescription(), "no twin, no line")

        setEntityGaussianTwin(entityId: entity, payloadURL: payload)
        let description = try XCTUnwrap(model.liveTwinDescription())
        XCTAssertTrue(description.hasPrefix("armed"), description)
        XCTAssertEqual(GaussianTwinInspector.stateTitle(.crossFading), "cross-fading")
        XCTAssertEqual(GaussianTwinInspector.stateTitle(.swapped), "swapped")
        removeEntityGaussianTwin(entityId: entity)
    }
}
