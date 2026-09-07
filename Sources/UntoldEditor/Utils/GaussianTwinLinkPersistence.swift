//
//  GaussianTwinLinkPersistence.swift
//  UntoldEditor
//
//  Where the Inspector's Splat Twin section reads and writes a mesh entity's link to its
//  cooked `.untoldgs` twin: the `gaussianAsset` record of the `.untold` file the entity was
//  placed from, patched through the engine's `UntoldAssetPatcher`, mirrored onto the live
//  `GaussianAssetLinkComponent` of every entity backed by that record, and previewed in the
//  viewport through `UntoldGaussianTwins` while the View > Preview Splat Twins toggle is on.
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import UntoldEngine
import UntoldGaussianTwins

/// The `.untold` file and the entity-table record a scene entity's twin link is stored in.
struct GaussianTwinLinkTarget: Equatable {
    let untoldURL: URL
    /// `UntoldEntityRecordV1.entityId` of the record: the key of the `gaussianAsset` table.
    let entityRecordId: UInt32
}

enum GaussianTwinLinkError: LocalizedError, Equatable {
    /// The entity is not a mesh placed from a `.untold` file (a primitive, a light, a splat).
    case notBackedByUntold
    /// The entity is backed by a `.untold` file whose entity table has no record for it — the
    /// root of a multi-node asset, or an asset re-exported since it was placed.
    case noEntityRecord(URL)
    case payloadNotFound(URL)
    /// Not a version 3 `.untoldgs`; the reason is the engine's.
    case invalidPayload(URL, String)
    case readFailed(URL, String)
    case patchFailed(String)
    case writeFailed(URL, String)

    var errorDescription: String? {
        switch self {
        case .notBackedByUntold:
            return "Only meshes placed from a .untold asset can have a splat twin."
        case let .noEntityRecord(url):
            return "\(url.lastPathComponent) has no entity record for this node; select one of its mesh nodes."
        case let .payloadNotFound(url):
            return "Payload not found: \(url.path)"
        case let .invalidPayload(url, reason):
            return "\(url.lastPathComponent) is not a usable .untoldgs payload: \(reason). Cook the source with Cook to .untoldgs… first."
        case let .readFailed(url, reason):
            return "Could not read \(url.lastPathComponent): \(reason)"
        case let .patchFailed(reason):
            return reason
        case let .writeFailed(url, reason):
            return "Could not write \(url.lastPathComponent): \(reason)"
        }
    }
}

extension Notification.Name {
    /// Posted after a twin link was written to or removed from a `.untold` file. `userInfo`
    /// carries `GaussianTwinLinkPersistence.targetUserInfoKey` → `GaussianTwinLinkTarget`.
    static let gaussianTwinLinkDidChange = Notification.Name("gaussianTwinLinkDidChange")
}

enum GaussianTwinLinkPersistence {
    static let targetUserInfoKey = "target"

    // MARK: - Target resolution

    /// The `.untold` file and entity record a scene entity's link lives in, or nil when the
    /// entity is not backed by a `.untold` file. The root of a single-node asset maps to the
    /// file's mesh-bearing record; a derived mesh node maps to the record whose node path
    /// matches its `DerivedAssetNodeComponent`. The root of a multi-node asset carries no
    /// mesh of its own and is not a target (its nodes are). Reads and decodes the file.
    static func resolveTarget(entityId: EntityID) -> GaussianTwinLinkTarget? {
        try? resolveTargetOrThrow(entityId: entityId)
    }

    static func resolveTargetOrThrow(entityId: EntityID) throws -> GaussianTwinLinkTarget {
        guard let untoldURL = resolveUntoldURL(entityId: entityId) else {
            throw GaussianTwinLinkError.notBackedByUntold
        }
        let decoded = try readDecodedAsset(at: untoldURL)
        return try resolveTarget(entityId: entityId, untoldURL: untoldURL, decoded: decoded)
    }

    /// `resolveTargetOrThrow` on an already decoded file.
    static func resolveTarget(entityId: EntityID, untoldURL: URL, decoded: UntoldDecodedAsset) throws -> GaussianTwinLinkTarget {
        guard hasComponent(entityId: entityId, componentType: RenderComponent.self) else {
            throw GaussianTwinLinkError.notBackedByUntold
        }
        guard let record = resolveEntityRecordForMesh(entityId: entityId, meshIndex: 0, decoded: decoded) else {
            throw GaussianTwinLinkError.noEntityRecord(untoldURL)
        }
        return GaussianTwinLinkTarget(untoldURL: untoldURL, entityRecordId: record.entityId)
    }

    /// The `.untold` file behind a mesh entity, without reading it: the asset instance's file
    /// for a derived mesh node, the render component's for a single-node asset root. Nil for
    /// a multi-node asset root (no mesh of its own), a derived node without a mesh, and
    /// anything not placed from a `.untold` file.
    static func resolveUntoldURL(entityId: EntityID) -> URL? {
        guard hasComponent(entityId: entityId, componentType: RenderComponent.self) else { return nil }
        if isDerivedAssetNode(entityId), isBindableAssetMeshNode(entityId) == false {
            return nil
        }
        return resolveUntoldAssetURL(entityId: entityId)?.standardizedFileURL
    }

    // MARK: - Reading

    /// The link the entity's `.untold` record carries, nil when there is none (or the entity
    /// resolves to no target).
    static func readTwinLink(entityId: EntityID) -> UntoldAssetPatcher.GaussianAssetLink? {
        guard let target = resolveTarget(entityId: entityId) else { return nil }
        return try? readTwinLink(target: target)
    }

    static func readTwinLink(target: GaussianTwinLinkTarget) throws -> UntoldAssetPatcher.GaussianAssetLink? {
        let fileData = try readFileData(at: target.untoldURL)
        do {
            return try UntoldAssetPatcher.gaussianAssets(in: fileData)[target.entityRecordId]
        } catch let error as UntoldAssetPatcher.Error {
            throw GaussianTwinLinkError.patchFailed(error.description)
        }
    }

    // MARK: - Writing

    /// Writes `link` as the record of the entity's `.untold` target (atomically), mirrors it
    /// onto the `GaussianAssetLinkComponent` of this entity and of every other scene entity
    /// backed by the same file and record, and updates the viewport preview when it is on.
    static func writeTwinLink(entityId: EntityID, link: UntoldAssetPatcher.GaussianAssetLink) throws {
        let target = try resolveTargetOrThrow(entityId: entityId)
        try writeTwinLink(target: target, link: link)
    }

    static func writeTwinLink(target: GaussianTwinLinkTarget, link: UntoldAssetPatcher.GaussianAssetLink) throws {
        let fileData = try readFileData(at: target.untoldURL)
        let patched: Data
        do {
            patched = try UntoldAssetPatcher.settingGaussianAsset(link, onEntity: target.entityRecordId, in: fileData)
        } catch let error as UntoldAssetPatcher.Error {
            throw GaussianTwinLinkError.patchFailed(error.description)
        }
        try write(patched, to: target.untoldURL)
        applyToScene(target: target, link: link)
    }

    /// Removes the entity's record from its `.untold` target, the `GaussianAssetLinkComponent`
    /// from every entity backed by it, and the previewed twin.
    static func removeTwinLink(entityId: EntityID) throws {
        let target = try resolveTargetOrThrow(entityId: entityId)
        try removeTwinLink(target: target)
    }

    static func removeTwinLink(target: GaussianTwinLinkTarget) throws {
        let fileData = try readFileData(at: target.untoldURL)
        let patched: Data
        do {
            patched = try UntoldAssetPatcher.removingGaussianAsset(onEntity: target.entityRecordId, in: fileData)
        } catch let error as UntoldAssetPatcher.Error {
            throw GaussianTwinLinkError.patchFailed(error.description)
        }
        if patched != fileData {
            try write(patched, to: target.untoldURL)
        }
        applyToScene(target: target, link: nil)
    }

    /// Writes or removes according to `link`; the undo stack restores whole links through this.
    static func restoreTwinLink(target: GaussianTwinLinkTarget, link: UntoldAssetPatcher.GaussianAssetLink?) throws {
        if let link {
            try writeTwinLink(target: target, link: link)
        } else {
            try removeTwinLink(target: target)
        }
    }

    // MARK: - Link construction

    /// The path written into the record: relative to the `.untold` file's directory when the
    /// payload sits inside or beside it (`../../Gaussians/chair.untoldgs`), else the bare
    /// file name — the runtime resolves that next to the `.untold` file it loads, so the
    /// caller should warn. Mirrors the engine CLI's `gaussian-link` rule.
    static func storedPayloadPath(payloadURL: URL, untoldURL: URL) -> (path: String, isRelative: Bool) {
        let directory = untoldURL.deletingLastPathComponent().standardizedFileURL
        let payload = payloadURL.standardizedFileURL
        if let relative = relativePath(of: payload, inside: directory) {
            return (relative, true)
        }
        if let relative = relativePath(of: payload.resolvingSymlinksInPath(), inside: directory.resolvingSymlinksInPath()) {
            return (relative, true)
        }
        return (payloadURL.lastPathComponent, false)
    }

    private static func relativePath(of file: URL, inside directory: URL) -> String? {
        let directory = directory.pathComponents
        let file = file.pathComponents
        guard file.count > directory.count, Array(file.prefix(directory.count)) == directory else {
            return nil
        }
        return file.dropFirst(directory.count).joined(separator: "/")
    }

    /// The link for a payload: the file must be a version 3 `.untoldgs`; its header fills one
    /// LOD level with the file's splat count. Settings default to the record's defaults.
    static func makeLink(
        payloadURL: URL,
        untoldURL: URL,
        swapDistanceMeters: Float = 0,
        occluderShrinkMeters: Float = 0.02,
        exposureOffsetEV: Float = 0
    ) throws -> UntoldAssetPatcher.GaussianAssetLink {
        guard FileManager.default.fileExists(atPath: payloadURL.path) else {
            throw GaussianTwinLinkError.payloadNotFound(payloadURL)
        }
        let header: UntoldGSHeaderV3
        do {
            header = try UntoldGSFormat.readHeaderV3(from: payloadURL)
        } catch let error as UntoldGSError {
            throw GaussianTwinLinkError.invalidPayload(payloadURL, error.description)
        } catch {
            throw GaussianTwinLinkError.invalidPayload(payloadURL, error.localizedDescription)
        }
        return UntoldAssetPatcher.GaussianAssetLink(
            payloadPath: storedPayloadPath(payloadURL: payloadURL, untoldURL: untoldURL).path,
            flags: UntoldGaussianAssetFlags.meshTwin,
            lodCount: 1,
            lodSplatCounts: [header.splatCount],
            lodSwitchScreenHeights: [0],
            occluderShrinkMeters: occluderShrinkMeters,
            exposureOffsetEV: exposureOffsetEV,
            swapDistanceMeters: swapDistanceMeters
        )
    }

    /// Where a stored payload path points when the `.untold` file is loaded: an absolute path
    /// as is, a relative one next to the file, and — like the engine loader — the bare file
    /// name beside the file when the relative path does not exist.
    static func resolvedPayloadURL(path: String, untoldURL: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        let directory = untoldURL.deletingLastPathComponent()
        let relative = directory.appendingPathComponent(path).standardizedFileURL
        if FileManager.default.fileExists(atPath: relative.path) {
            return relative
        }
        let basename = (path as NSString).lastPathComponent
        let flattened = directory.appendingPathComponent(basename).standardizedFileURL
        return FileManager.default.fileExists(atPath: flattened.path) ? flattened : relative
    }

    // MARK: - Scene mirroring

    /// Every scene entity whose link lives in `target`: the selected node and any other
    /// placement of the same asset.
    static func entitiesBacked(by target: GaussianTwinLinkTarget) -> [EntityID] {
        let renderId = getComponentId(for: RenderComponent.self)
        let candidates = queryEntitiesWithComponentIds([renderId], in: scene).filter { entityId in
            resolveUntoldURL(entityId: entityId) == target.untoldURL
        }
        guard !candidates.isEmpty, let decoded = try? readDecodedAsset(at: target.untoldURL) else {
            return []
        }
        return candidates.filter { entityId in
            resolveEntityRecordForMesh(entityId: entityId, meshIndex: 0, decoded: decoded)?.entityId == target.entityRecordId
        }
    }

    /// Mirrors the persisted record onto the live scene (`GaussianAssetLinkComponent` and the
    /// preview) for every entity backed by `target`, then posts `.gaussianTwinLinkDidChange`.
    static func applyToScene(target: GaussianTwinLinkTarget, link: UntoldAssetPatcher.GaussianAssetLink?) {
        for entityId in entitiesBacked(by: target) {
            applyLinkComponent(link, to: entityId, untoldURL: target.untoldURL)
            applyPreview(entityId: entityId)
        }
        NotificationCenter.default.post(
            name: .gaussianTwinLinkDidChange,
            object: nil,
            userInfo: [targetUserInfoKey: target]
        )
    }

    /// Sets (or removes, for nil) the `GaussianAssetLinkComponent` the engine loader would
    /// have attached had the file carried `link` when the entity was placed.
    static func applyLinkComponent(_ link: UntoldAssetPatcher.GaussianAssetLink?, to entityId: EntityID, untoldURL: URL) {
        guard let link else {
            if hasComponent(entityId: entityId, componentType: GaussianAssetLinkComponent.self) {
                scene.remove(component: GaussianAssetLinkComponent.self, from: entityId)
            }
            return
        }
        if scene.get(component: GaussianAssetLinkComponent.self, for: entityId) == nil {
            registerComponent(entityId: entityId, componentType: GaussianAssetLinkComponent.self)
        }
        guard let component = scene.get(component: GaussianAssetLinkComponent.self, for: entityId) else { return }
        component.payloadURL = resolvedPayloadURL(path: link.payloadPath, untoldURL: untoldURL)
        component.flags = link.flags
        component.lodCount = link.lodCount
        component.lodSplatCounts = link.lodSplatCounts
        component.lodSwitchScreenHeights = link.lodSwitchScreenHeights
        component.occluderShrinkMeters = link.occluderShrinkMeters
        component.exposureOffsetEV = link.exposureOffsetEV
        component.swapDistanceMeters = link.swapDistanceMeters
    }

    /// Brings the viewport twin in line with the entity's `GaussianAssetLinkComponent`: a
    /// twin whose payload did not change only takes the new options (no reload); a new
    /// payload relinks; no link unlinks. Nothing is linked while the preview is off, but a
    /// stale twin is still dropped.
    static func applyPreview(entityId: EntityID) {
        let component = scene.get(component: GaussianAssetLinkComponent.self, for: entityId)
        guard let component, component.isMeshTwin, let payloadURL = component.payloadURL else {
            if hasComponent(entityId: entityId, componentType: GaussianTwinComponent.self) {
                removeEntityGaussianTwin(entityId: entityId)
            }
            return
        }
        guard GaussianTwinPreviewSettings.shared.isEnabled else { return }
        let options = GaussianTwinOptions(link: component)
        if let twin = scene.get(component: GaussianTwinComponent.self, for: entityId), twin.payloadURL == payloadURL {
            twin.options = options
        } else {
            setEntityGaussianTwin(entityId: entityId, payloadURL: payloadURL, options: options)
        }
    }

    // MARK: - File access

    private static func readFileData(at url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw GaussianTwinLinkError.readFailed(url, error.localizedDescription)
        }
    }

    private static func readDecodedAsset(at url: URL) throws -> UntoldDecodedAsset {
        let fileData = try readFileData(at: url)
        do {
            return try UntoldReader().readAsset(from: fileData)
        } catch {
            throw GaussianTwinLinkError.readFailed(url, String(describing: error))
        }
    }

    private static func write(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw GaussianTwinLinkError.writeFailed(url, error.localizedDescription)
        }
    }
}
