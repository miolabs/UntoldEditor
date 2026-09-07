//
//  GaussianTwinLinkPersistenceTests.swift
//  UntoldEditorTests
//
//  The Splat Twin link's home on disk: the `.untold` file's gaussianAsset record, read and
//  written through the engine patcher, mirrored onto the scene's link components.
//

import Foundation
@testable import UntoldEditor
@testable import UntoldEngine
import UntoldGaussianTwins
import XCTest

final class GaussianTwinLinkPersistenceTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        scene = Scene()
        directory = try GaussianTwinTestFixtures.makeTemporaryDirectory()
    }

    override func tearDown() {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        directory = nil
        super.tearDown()
    }

    // MARK: - Target resolution

    func test_resolveTarget_singleNodeRootMapsToTheMeshRecord() throws {
        let untold = try GaussianTwinTestFixtures.writeUntold(to: directory)
        let entity = GaussianTwinTestFixtures.makeMeshEntity(assetURL: untold)

        let target = try GaussianTwinLinkPersistence.resolveTargetOrThrow(entityId: entity)
        XCTAssertEqual(target, GaussianTwinLinkTarget(untoldURL: untold.standardizedFileURL, entityRecordId: 0))
    }

    func test_resolveTarget_derivedMeshNodeMapsToItsOwnRecord() throws {
        let untold = try GaussianTwinTestFixtures.writeUntold(to: directory, hierarchy: true)
        let placed = GaussianTwinTestFixtures.makeAssetInstance(assetURL: untold, nodePath: GaussianTwinTestFixtures.hierarchyChildNodePath)

        let target = try GaussianTwinLinkPersistence.resolveTargetOrThrow(entityId: placed.node)
        XCTAssertEqual(target.untoldURL, untold.standardizedFileURL)
        XCTAssertEqual(target.entityRecordId, 1, "the child's record, not the root's")
    }

    func test_resolveTarget_multiNodeRootAndMeshlessNodeAreNotTargets() throws {
        let untold = try GaussianTwinTestFixtures.writeUntold(to: directory, hierarchy: true)
        let placed = GaussianTwinTestFixtures.makeAssetInstance(assetURL: untold, nodePath: GaussianTwinTestFixtures.hierarchyChildNodePath, withMesh: false)

        XCTAssertNil(GaussianTwinLinkPersistence.resolveUntoldURL(entityId: placed.root), "a multi-node root has no mesh of its own")
        XCTAssertNil(GaussianTwinLinkPersistence.resolveTarget(entityId: placed.root))
        XCTAssertNil(GaussianTwinLinkPersistence.resolveTarget(entityId: placed.node), "a transform-only node is not a target")
        XCTAssertThrowsError(try GaussianTwinLinkPersistence.resolveTargetOrThrow(entityId: placed.root)) { error in
            XCTAssertEqual(error as? GaussianTwinLinkError, .notBackedByUntold)
        }
    }

    func test_resolveTarget_lightAndPrimitiveAreNotTargets() {
        let light = createEntity()
        registerComponent(entityId: light, componentType: LocalTransformComponent.self)
        registerComponent(entityId: light, componentType: DirectionalLightComponent.self)
        XCTAssertNil(GaussianTwinLinkPersistence.resolveTarget(entityId: light))

        let primitive = GaussianTwinTestFixtures.makeMeshEntity(name: "Cube", assetURL: URL(fileURLWithPath: "/dev/null/cube.usdc"))
        XCTAssertNil(GaussianTwinLinkPersistence.resolveUntoldURL(entityId: primitive), "only .untold-backed meshes")
    }

    func test_resolveTarget_recordMismatchIsReportedNotSwallowed() throws {
        let untold = try GaussianTwinTestFixtures.writeUntold(to: directory, hierarchy: true)
        let placed = GaussianTwinTestFixtures.makeAssetInstance(assetURL: untold, nodePath: "Root/root_entity#0/renamed#7")

        XCTAssertThrowsError(try GaussianTwinLinkPersistence.resolveTargetOrThrow(entityId: placed.node)) { error in
            XCTAssertEqual(error as? GaussianTwinLinkError, .noEntityRecord(untold.standardizedFileURL))
        }
    }

    // MARK: - Round trip

    func test_writeReadRemove_roundTripsThroughTheUntoldFile() throws {
        let untold = try GaussianTwinTestFixtures.writeUntold(to: directory)
        let payload = try GaussianTwinTestFixtures.writeUntoldGS(to: directory.appendingPathComponent("Chair.untoldgs"), splatCount: 5)
        let entity = GaussianTwinTestFixtures.makeMeshEntity(assetURL: untold)
        XCTAssertNil(GaussianTwinLinkPersistence.readTwinLink(entityId: entity))

        let link = try GaussianTwinLinkPersistence.makeLink(
            payloadURL: payload,
            untoldURL: untold,
            swapDistanceMeters: 8,
            occluderShrinkMeters: 0.03,
            exposureOffsetEV: -0.5
        )
        XCTAssertEqual(link.payloadPath, "Chair.untoldgs")
        XCTAssertEqual(link.lodCount, 1)
        XCTAssertEqual(link.lodSplatCounts, [5])
        XCTAssertEqual(link.lodSwitchScreenHeights, [0])
        XCTAssertEqual(link.flags, UntoldGaussianAssetFlags.meshTwin)

        try GaussianTwinLinkPersistence.writeTwinLink(entityId: entity, link: link)

        // The file carries the record and still reads (hash valid, alignment kept).
        let decoded = try UntoldReader().readAsset(from: Data(contentsOf: untold))
        XCTAssertEqual(decoded.gaussianAssets.count, 1)
        XCTAssertEqual(decoded.gaussianAssets.first?.entityId, 0)
        XCTAssertEqual(decoded.gaussianAssets.first?.swapDistanceMeters, 8)
        XCTAssertEqual(GaussianTwinLinkPersistence.readTwinLink(entityId: entity), link)

        // Mirrored onto the entity as the loader would have attached it.
        let component = try XCTUnwrap(scene.get(component: GaussianAssetLinkComponent.self, for: entity))
        XCTAssertTrue(component.isMeshTwin)
        XCTAssertEqual(component.payloadURL?.standardizedFileURL, payload.standardizedFileURL)
        XCTAssertEqual(component.swapDistanceMeters, 8)
        XCTAssertEqual(component.occluderShrinkMeters, 0.03)
        XCTAssertEqual(component.exposureOffsetEV, -0.5)
        XCTAssertEqual(component.lodSplatCounts, [5])

        // A second write replaces the record.
        var tweaked = link
        tweaked.swapDistanceMeters = 3
        try GaussianTwinLinkPersistence.writeTwinLink(entityId: entity, link: tweaked)
        XCTAssertEqual(try UntoldReader().readAsset(from: Data(contentsOf: untold)).gaussianAssets.count, 1)
        XCTAssertEqual(GaussianTwinLinkPersistence.readTwinLink(entityId: entity)?.swapDistanceMeters, 3)
        XCTAssertEqual(scene.get(component: GaussianAssetLinkComponent.self, for: entity)?.swapDistanceMeters, 3)

        try GaussianTwinLinkPersistence.removeTwinLink(entityId: entity)
        XCTAssertNil(GaussianTwinLinkPersistence.readTwinLink(entityId: entity))
        XCTAssertTrue(try UntoldReader().readAsset(from: Data(contentsOf: untold)).gaussianAssets.isEmpty)
        XCTAssertNil(scene.get(component: GaussianAssetLinkComponent.self, for: entity))
        XCTAssertNil(scene.get(component: GaussianTwinComponent.self, for: entity), "the previewed twin goes with the link")
    }

    func test_write_mirrorsOntoEveryPlacementOfTheSameRecord() throws {
        let untold = try GaussianTwinTestFixtures.writeUntold(to: directory)
        let payload = try GaussianTwinTestFixtures.writeUntoldGS(to: directory.appendingPathComponent("Chair.untoldgs"))
        let first = GaussianTwinTestFixtures.makeMeshEntity(name: "Chair", assetURL: untold)
        let second = GaussianTwinTestFixtures.makeMeshEntity(name: "Chair 2", assetURL: untold)
        let otherAsset = try GaussianTwinTestFixtures.writeUntold(to: directory, name: "Table")
        let unrelated = GaussianTwinTestFixtures.makeMeshEntity(name: "Table", assetURL: otherAsset)

        let target = try GaussianTwinLinkPersistence.resolveTargetOrThrow(entityId: first)
        XCTAssertEqual(Set(GaussianTwinLinkPersistence.entitiesBacked(by: target)), [first, second])

        let link = try GaussianTwinLinkPersistence.makeLink(payloadURL: payload, untoldURL: untold)
        try GaussianTwinLinkPersistence.writeTwinLink(entityId: first, link: link)
        XCTAssertNotNil(scene.get(component: GaussianAssetLinkComponent.self, for: second))
        XCTAssertNil(scene.get(component: GaussianAssetLinkComponent.self, for: unrelated))
        XCTAssertNil(GaussianTwinLinkPersistence.readTwinLink(entityId: unrelated), "the other file is untouched")
    }

    func test_write_onDerivedNodeSetsTheChildRecord() throws {
        let untold = try GaussianTwinTestFixtures.writeUntold(to: directory, hierarchy: true)
        let payload = try GaussianTwinTestFixtures.writeUntoldGS(to: directory.appendingPathComponent("child.untoldgs"))
        let placed = GaussianTwinTestFixtures.makeAssetInstance(assetURL: untold, nodePath: GaussianTwinTestFixtures.hierarchyChildNodePath)

        let link = try GaussianTwinLinkPersistence.makeLink(payloadURL: payload, untoldURL: untold)
        try GaussianTwinLinkPersistence.writeTwinLink(entityId: placed.node, link: link)

        let links = try UntoldAssetPatcher.gaussianAssets(in: Data(contentsOf: untold))
        XCTAssertEqual(Array(links.keys), [1])
        XCTAssertNotNil(scene.get(component: GaussianAssetLinkComponent.self, for: placed.node))
        XCTAssertNil(scene.get(component: GaussianAssetLinkComponent.self, for: placed.root))
    }

    // MARK: - Payload path and validation

    func test_storedPayloadPath_isRelativeInsideTheAssetFolderElseTheBasename() throws {
        let models = directory.appendingPathComponent("GameData/Models/Chair", isDirectory: true)
        let gaussians = directory.appendingPathComponent("GameData/Gaussians", isDirectory: true)
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gaussians, withIntermediateDirectories: true)
        let untold = models.appendingPathComponent("Chair.untold")

        let beside = GaussianTwinLinkPersistence.storedPayloadPath(payloadURL: models.appendingPathComponent("Chair.untoldgs"), untoldURL: untold)
        XCTAssertEqual(beside.path, "Chair.untoldgs")
        XCTAssertTrue(beside.isRelative)

        let nested = GaussianTwinLinkPersistence.storedPayloadPath(payloadURL: models.appendingPathComponent("splats/Chair.untoldgs"), untoldURL: untold)
        XCTAssertEqual(nested.path, "splats/Chair.untoldgs")

        // A sibling folder is outside the .untold's directory: the runtime cannot reach it
        // through a relative path, so only the file name is stored (the caller warns).
        let sibling = GaussianTwinLinkPersistence.storedPayloadPath(payloadURL: gaussians.appendingPathComponent("chair_capture.untoldgs"), untoldURL: untold)
        XCTAssertEqual(sibling.path, "chair_capture.untoldgs")
        XCTAssertFalse(sibling.isRelative)

        let elsewhere = GaussianTwinLinkPersistence.storedPayloadPath(payloadURL: URL(fileURLWithPath: "/Volumes/Captures/chair.untoldgs"), untoldURL: untold)
        XCTAssertEqual(elsewhere.path, "chair.untoldgs")
        XCTAssertFalse(elsewhere.isRelative)
    }

    func test_resolvedPayloadURL_followsTheLoaderRules() throws {
        let untold = directory.appendingPathComponent("Chair.untold")
        try GaussianTwinTestFixtures.writeUntoldGS(to: directory.appendingPathComponent("Chair.untoldgs"))

        XCTAssertEqual(
            GaussianTwinLinkPersistence.resolvedPayloadURL(path: "Chair.untoldgs", untoldURL: untold),
            directory.appendingPathComponent("Chair.untoldgs").standardizedFileURL
        )
        XCTAssertEqual(
            GaussianTwinLinkPersistence.resolvedPayloadURL(path: "moved/away/Chair.untoldgs", untoldURL: untold),
            directory.appendingPathComponent("Chair.untoldgs").standardizedFileURL,
            "a relative path that no longer exists falls back to the basename beside the file"
        )
        XCTAssertEqual(
            GaussianTwinLinkPersistence.resolvedPayloadURL(path: "/abs/Chair.untoldgs", untoldURL: untold).path,
            "/abs/Chair.untoldgs"
        )
    }

    func test_makeLink_rejectsMissingAndNonV3Payloads() throws {
        let untold = try GaussianTwinTestFixtures.writeUntold(to: directory)
        let missing = directory.appendingPathComponent("missing.untoldgs")
        XCTAssertThrowsError(try GaussianTwinLinkPersistence.makeLink(payloadURL: missing, untoldURL: untold)) { error in
            XCTAssertEqual(error as? GaussianTwinLinkError, .payloadNotFound(missing))
        }

        let stale = try GaussianTwinTestFixtures.writeStalePayload(to: directory.appendingPathComponent("stale.untoldgs"))
        XCTAssertThrowsError(try GaussianTwinLinkPersistence.makeLink(payloadURL: stale, untoldURL: untold)) { error in
            guard case let .invalidPayload(url, reason)? = error as? GaussianTwinLinkError else {
                return XCTFail("expected invalidPayload, got \(error)")
            }
            XCTAssertEqual(url, stale)
            XCTAssertTrue(reason.contains("version"), reason)
            XCTAssertTrue(error.localizedDescription.contains("not a usable .untoldgs payload"), "user-visible message")
        }

        let ply = directory.appendingPathComponent("raw.ply")
        try Data("ply\nformat binary_little_endian 1.0\n".utf8).write(to: ply)
        XCTAssertThrowsError(try GaussianTwinLinkPersistence.makeLink(payloadURL: ply, untoldURL: untold)) { error in
            guard case .invalidPayload? = error as? GaussianTwinLinkError else {
                return XCTFail("expected invalidPayload, got \(error)")
            }
        }
    }

    func test_write_reportsUnknownRecordAsPatchFailure() throws {
        let untold = try GaussianTwinTestFixtures.writeUntold(to: directory)
        let payload = try GaussianTwinTestFixtures.writeUntoldGS(to: directory.appendingPathComponent("Chair.untoldgs"))
        let link = try GaussianTwinLinkPersistence.makeLink(payloadURL: payload, untoldURL: untold)
        let bogus = GaussianTwinLinkTarget(untoldURL: untold, entityRecordId: 42)

        XCTAssertThrowsError(try GaussianTwinLinkPersistence.writeTwinLink(target: bogus, link: link)) { error in
            guard case let .patchFailed(reason)? = error as? GaussianTwinLinkError else {
                return XCTFail("expected patchFailed, got \(error)")
            }
            XCTAssertTrue(reason.contains("42"), reason)
        }
        XCTAssertTrue(try UntoldReader().readAsset(from: Data(contentsOf: untold)).gaussianAssets.isEmpty, "the file is left alone")
    }
}
