//
//  GaussianTwinAlignMode.swift
//  UntoldEditor
//
//  The Splat Twin section's align mode: while it is on, the twins of the entities being
//  aligned are forced to show over their meshes so the alignment (offset, yaw, scale) can be
//  judged against the surface the splat should sit on. Nothing of it is persisted.
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

/// One align mode for the editor: entered by a `GaussianTwinInspectorModel` for every
/// placement of the record it edits, left by that model (toggle, deinit, link removed) or by
/// whoever tears the preview down (scene reset, View > Preview Splat Twins off). Entering
/// turns the engine's occluder shells off (`GaussianDebugOptions.disableOccluderShell`) and
/// gives the entities' twins a zero swap distance and `showsMeshWhileSwapped`, through
/// `GaussianTwinLinkPersistence.previewOptions`; leaving restores the debug option to what it
/// was and re-applies the links' own options. The links on disk never change.
final class GaussianTwinAlignMode: ObservableObject {
    /// Main-thread state, like the rest of the editor's UI models.
    nonisolated(unsafe) static let shared = GaussianTwinAlignMode()

    /// The entities whose preview is overridden; empty when the mode is off.
    @Published private(set) var entities: Set<EntityID> = []
    /// The model that entered, so a second inspector or a deinit can tell whose mode it is.
    private(set) var owner: ObjectIdentifier?
    /// `GaussianDebugOptions.disableOccluderShell` as found on entering, put back on leaving.
    private var restoredDisableOccluderShell = false

    var isActive: Bool {
        owner != nil
    }

    /// Whether `object` is the one that entered.
    func isOwned(by object: AnyObject) -> Bool {
        owner == ObjectIdentifier(object)
    }

    /// Enters (or, when another owner had it, takes over) for `entities`; nothing happens
    /// for an empty set. The previews of the entities are updated at once.
    func enter(owner object: AnyObject, entities newEntities: Set<EntityID>) {
        guard !newEntities.isEmpty else { return }
        if isActive {
            leave()
        }
        restoredDisableOccluderShell = GaussianDebugOptions.shared.disableOccluderShell
        GaussianDebugOptions.shared.disableOccluderShell = true
        owner = ObjectIdentifier(object)
        entities = newEntities
        reapplyPreviews(newEntities)
    }

    /// Leaves when `object` is the owner (a model going away must not end a mode another
    /// model entered since).
    func leave(owner object: AnyObject) {
        guard isOwned(by: object) else { return }
        leave()
    }

    /// Restores the debug option and the entities' own preview options. No-op when off.
    func leave() {
        guard isActive else { return }
        GaussianDebugOptions.shared.disableOccluderShell = restoredDisableOccluderShell
        let previous = entities
        owner = nil
        entities = []
        reapplyPreviews(previous)
    }

    /// The options the preview runs for `entityId`: `options` as the link asks for them, or
    /// forced to show the twin over the mesh while the entity is being aligned.
    func previewOptions(for entityId: EntityID, options: GaussianTwinOptions) -> GaussianTwinOptions {
        guard entities.contains(entityId) else { return options }
        var forced = options
        forced.swapDistanceMeters = 0
        forced.showsMeshWhileSwapped = true
        return forced
    }

    private func reapplyPreviews(_ entities: Set<EntityID>) {
        for entityId in entities {
            GaussianTwinLinkPersistence.applyPreview(entityId: entityId)
        }
    }
}
