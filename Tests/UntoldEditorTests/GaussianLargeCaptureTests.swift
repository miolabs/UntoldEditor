//
//  GaussianLargeCaptureTests.swift
//  UntoldEditorTests
//
//  The editor's plain-Gaussian path end to end, headless: a `.ply` imported into a temporary
//  project's Gaussians folder, cooked through the cook sheet's defaults (`cookGaussianPLY`),
//  placed through `loadEditorGaussianAuto` (the call a drop or double-click makes) and rendered
//  with the editor's renderer at 1920×1080 from three poses and an orbit, with the splat-twin
//  preview on and off — a plain entity must draw the same either way.
//
//  The 200-splat fixture always runs. `UNTOLD_EDITOR_LARGE_CAPTURE=<path to .ply or .untoldgs>`
//  runs the same steps on a real capture, prints a `[LargeCapture]` report block (cook wall
//  time and peak footprint, which engine path the entity took, per-pose GPU and CPU frame
//  times, working set, pool, quotas, levels and paging counters), then repeats the poses with
//  paging and the coarse levels off for an A/B. `UNTOLD_EDITOR_LARGE_CAPTURE_OUTPUT=<dir>`
//  keeps the temporary project (and the cooked file) there instead of the temp folder.
//

import CShaderTypes
import Darwin
import Metal
import simd
@testable import UntoldEditor
@testable import UntoldEngine
import UntoldGaussianTwins
import XCTest

@MainActor
final class GaussianLargeCaptureTests: XCTestCase {
    static let captureEnvironmentKey = "UNTOLD_EDITOR_LARGE_CAPTURE"
    static let outputEnvironmentKey = "UNTOLD_EDITOR_LARGE_CAPTURE_OUTPUT"

    private let viewportWidth = 1920
    private let viewportHeight = 1080

    private var renderer: UntoldRenderer!
    private var projectURL: URL!
    private var keepProject = false
    private var cameraEntity: EntityID = .invalid
    private var entity: EntityID = .invalid
    private var twinDefaults: UserDefaults!
    private var twinSuiteName = ""
    private var twinPreview: GaussianTwinPreviewSettings?
    private var runtimeSettings: EditorGaussianRuntimeSettings?
    private var savedWorkingSetOverride: Int?

    private var savedFov: Float = 0
    private var savedNear: Float = 0
    private var savedFar: Float = 0
    private var savedDisablePaging = false
    private var savedLevelMode = GaussianLevelMode.auto
    private var savedLogLevel = Logger.logLevel
    private var savedGaussianLog = false
    private var report: [String] = []

    // MARK: - Set-up

    override func setUp() async throws {
        try await super.setUp()
        savedFov = fov
        savedNear = near
        savedFar = far
        savedDisablePaging = GaussianDebugOptions.shared.disablePaging
        savedLevelMode = GaussianDebugOptions.shared.gaussianLevelMode
        savedLogLevel = Logger.logLevel
        savedGaussianLog = Logger.isEnabled(category: .gaussian)
        GaussianDebugOptions.shared.disablePaging = false
        GaussianDebugOptions.shared.gaussianLevelMode = .auto
        GaussianSharedWorkingSet.shared.resetBudgetHysteresis()

        // The editor's renderer, headless: no window, a 1× drawable of the viewport size, the
        // editor's render extension (highlight, light visuals, gizmo) registered as EditorView does.
        let renderer = try XCTUnwrap(UntoldRenderer.create(configuration: .editor), "the editor renderer")
        self.renderer = renderer
        registerEditorRenderExtension()
        let size = CGSize(width: viewportWidth, height: viewportHeight)
        renderer.metalView.autoResizeDrawable = false
        renderer.metalView.drawableSize = size
        (renderer.metalView.layer as? CAMetalLayer)?.contentsScale = 1.0
        renderer.metalView.frame = NSRect(x: 0, y: 0, width: viewportWidth, height: viewportHeight)
        renderer.mtkView(renderer.metalView, drawableSizeWillChange: size)
        renderer.initSizeableResources()
        renderer.pendingResize = false
        renderer.metalView.delegate = nil
        gameMode = false
        activeEntity = .invalid
        gizmoActive = false

        let environment = ProcessInfo.processInfo.environment
        let outputRoot: URL
        if let output = environment[Self.outputEnvironmentKey], !output.isEmpty {
            outputRoot = URL(fileURLWithPath: output, isDirectory: true)
            keepProject = true
        } else {
            outputRoot = FileManager.default.temporaryDirectory
        }
        projectURL = outputRoot.appendingPathComponent("GaussianLargeCaptureTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: gaussiansFolder, withIntermediateDirectories: true)

        // The splat-twin preview as the editor owns it, on an isolated defaults suite so the
        // user's View > Preview Splat Twins preference is untouched; `.live` installs the real
        // GaussianTwinSystem.
        twinSuiteName = "GaussianLargeCaptureTests-\(UUID().uuidString)"
        twinDefaults = try XCTUnwrap(UserDefaults(suiteName: twinSuiteName))
        twinPreview = GaussianTwinPreviewSettings(defaults: twinDefaults, installer: .live)
        // The editor's runtime policy as EditorView installs it (View > Splat Debug > Working
        // Set, the editor default), on the same isolated suite.
        savedWorkingSetOverride = GaussianRuntimeLimits.workingSetSplatsOverride
        let runtimeSettings = EditorGaussianRuntimeSettings(defaults: twinDefaults)
        runtimeSettings.activate()
        self.runtimeSettings = runtimeSettings
    }

    override func tearDown() async throws {
        if entity != .invalid, scene.exists(entity) {
            removeEntityGaussian(entityId: entity)
            destroyEntity(entityId: entity)
        }
        if cameraEntity != .invalid, scene.exists(cameraEntity) {
            destroyEntity(entityId: cameraEntity)
        }
        CameraSystem.shared.activeCamera = nil
        EditorGaussianAssetState.shared.clear()
        twinPreview?.isEnabled = false
        GaussianTwinSystem.shared.uninstall()
        twinPreview = nil
        runtimeSettings?.deactivate()
        runtimeSettings = nil
        GaussianRuntimeLimits.workingSetSplatsOverride = savedWorkingSetOverride
        if let twinDefaults {
            twinDefaults.removePersistentDomain(forName: twinSuiteName)
        }
        twinDefaults = nil
        RenderExtensionRegistry.shared.unregister(id: EditorRenderExtension.shared.id)
        renderer = nil
        fov = savedFov
        near = savedNear
        far = savedFar
        GaussianDebugOptions.shared.disablePaging = savedDisablePaging
        GaussianDebugOptions.shared.gaussianLevelMode = savedLevelMode
        Logger.logLevel = savedLogLevel
        Logger.set(category: .gaussian, enabled: savedGaussianLog)
        if let projectURL, !keepProject {
            try? FileManager.default.removeItem(at: projectURL)
        }
        projectURL = nil
        try await super.tearDown()
    }

    private var gaussiansFolder: URL {
        projectURL.appendingPathComponent(AssetCategory.gaussians.rawValue, isDirectory: true)
    }

    // MARK: - Tests

    /// The always-on variant: the 200-splat fixture through import, cook, placement and a short
    /// render from every pose with the twin preview on and off.
    func test_fixtureCooksPlacesAndRendersThroughTheEditorPath() async throws {
        let source = projectURL.appendingPathComponent("chair.ply")
        try Self.makeFixturePLY(splatCount: 200).write(to: source)

        let outcome = try await runCapture(source: source, framesPerPose: 12, orbitFrames: 12, label: "fixture")

        XCTAssertEqual(outcome.header.splatCount, 200)
        XCTAssertEqual(outcome.header.chunkCount, 1)
        XCTAssertEqual(outcome.header.coarseLevelCount, 0, "a single chunk bakes no coarse levels")
        XCTAssertTrue(outcome.path.isChunked, "a cooked .untoldgs takes the per-chunk path")
        XCTAssertFalse(outcome.path.isPaged, "3 KiB is far below the paging threshold")
        XCTAssertFalse(outcome.path.hasCoarse)
        XCTAssertEqual(outcome.path.progressiveLevels, nil, "the sheet's default is a single tier")
        printReport()
    }

    /// The opt-in variant on a real capture (`UNTOLD_EDITOR_LARGE_CAPTURE`), plus the A/B with
    /// paging and the coarse levels off.
    func test_largeCaptureCooksPlacesAndRendersThroughTheEditorPath() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[Self.captureEnvironmentKey], !path.isEmpty else {
            throw XCTSkip("set \(Self.captureEnvironmentKey)=<path to .ply or .untoldgs> to run the large-capture test")
        }
        let source = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw XCTSkip("\(Self.captureEnvironmentKey) points at a missing file: \(source.path)")
        }

        let outcome = try await runCapture(source: source, framesPerPose: 120, orbitFrames: 90, label: "capture")

        XCTAssertTrue(outcome.path.isChunked, "a cooked .untoldgs takes the per-chunk path, not the whole-buffer fallback")
        let header = outcome.header
        if header.chunkCount >= 64 {
            XCTAssertGreaterThan(header.coarseLevelCount, 0, "the sheet's default (.automatic) bakes coarse levels for \(header.chunkCount) chunks")
            XCTAssertTrue(outcome.path.hasCoarse, "the coarse table is resident beside the entity")
        }
        let assetBytes = GaussianPagingPolicy.assetBytes(splatCount: Int(header.splatCount), shBytesPerSplat: header.shBytesPerSplat)
        let residencyBudget = GaussianPagingPolicy.residencyBudgetBytes()
        let threshold = GaussianPagingPolicy.pagingThresholdBytes(residencyBudgetBytes: residencyBudget)
        let expectPaged = GaussianPagingPolicy.shouldPage(assetBytes: assetBytes, thresholdBytes: threshold, allowPaging: true, disablePaging: false)
        XCTAssertEqual(outcome.path.isPaged, expectPaged, "\(assetBytes) packed bytes against a \(threshold)-byte threshold")

        // A/B: the same poses with every record resident and the fine records only.
        GaussianDebugOptions.shared.disablePaging = true
        GaussianDebugOptions.shared.gaussianLevelMode = .fineOnly
        twinPreview?.isEnabled = false
        removeEntityGaussian(entityId: entity)
        let abPlacement = try await place(asset: outcome.assetURL)
        note("A/B placement (disablePaging=true, levelMode=fineOnly): load \(ms(abPlacement.loadSeconds)) firstFrame \(ms(abPlacement.firstFrameSeconds)) path=\(abPlacement.path.description)")
        XCTAssertFalse(abPlacement.path.isPaged, "disablePaging loads the asset whole-resident")
        let abSuite = try XCTUnwrap(runPoseSuites(bounds: abPlacement.bounds, framesPerPose: 120, orbitFrames: 90, variants: [(label: "A/B paging off, fine only", apply: {})]).first)
        reportDelta(baseline: outcome.suites[0], variant: abSuite)
        GaussianDebugOptions.shared.disablePaging = false
        GaussianDebugOptions.shared.gaussianLevelMode = .auto
        printReport()
    }

    // MARK: - The steps

    struct EnginePath: CustomStringConvertible {
        var isChunked = false
        var isPaged = false
        var hasCoarse = false
        var coarseLevels = 0
        var chunkCount = 0
        var splatCount = 0
        var residentSplats = 0
        var estimatedGPUBytes = 0
        var poolBytes = 0
        var slotCount = 0
        var progressiveLevels: Int?
        var loadingMode = ""

        var description: String {
            "chunked=\(isChunked) paged=\(isPaged) coarse=\(hasCoarse)(levels \(coarseLevels)) chunks=\(chunkCount) splats=\(splatCount) residentSplats=\(residentSplats) gpuBytes=\(gaussianFormatBytes(estimatedGPUBytes)) pool=\(gaussianFormatBytes(poolBytes)) slots=\(slotCount) progressive=\(progressiveLevels.map(String.init) ?? "no") mode=\(loadingMode)"
        }
    }

    struct Placement {
        let path: EnginePath
        let bounds: (min: simd_float3, max: simd_float3)
        let loadSeconds: Double
        let firstFrameSeconds: Double
    }

    struct CaptureOutcome {
        let assetURL: URL
        let header: UntoldGSHeaderV3
        let path: EnginePath
        let suites: [PoseSuite]
    }

    /// Import, cook (a `.ply`), place, render with the preview on and off.
    private func runCapture(source: URL, framesPerPose: Int, orbitFrames: Int, label: String) async throws -> CaptureOutcome {
        note("== \(label): \(source.path) ==")
        note("editor: working set \(runtimeSettings?.workingSet.rawValue ?? "none") (\(GaussianSplatBudget.formatted(runtimeSettings?.workingSet.splatsInEffect ?? 0)) splats)")
        note("machine: geometryBudget=\(gaussianFormatBytes(MemoryBudgetManager.shared.geometryBudget)) residencyBudget=\(gaussianFormatBytes(GaussianPagingPolicy.residencyBudgetBytes())) pagingThreshold=\(gaussianFormatBytes(GaussianPagingPolicy.pagingThresholdBytes(residencyBudgetBytes: GaussianPagingPolicy.residencyBudgetBytes()))) workingSetBudget=\(GaussianSharedWorkingSet.budgetSplats()) splats (limit \(GaussianRuntimeLimits.workingSetSplats)) maxSplatsPerEntity=\(GaussianRuntimeLimits.maxSplatsPerEntity) maxSplatsPerPixel=\(GaussianRuntimeLimits.maxSplatsPerPixel)")

        // (a) Import into the project's Gaussians folder as the browser does: a folder package.
        let packageFolder = gaussianPackageFolder(for: source, in: gaussiansFolder)
        let importStart = CACurrentMediaTime()
        let imported = try importGaussianAsset(sourceURL: source, destinationFolder: packageFolder)
        note("import: \(imported.lastPathComponent) into \(packageFolder.lastPathComponent)/ in \(ms(CACurrentMediaTime() - importStart)) (\(gaussianFormatBytes(fileSize(source))))")

        // (b) Cook through the sheet's defaults.
        let assetURL: URL
        if imported.pathExtension.lowercased() == "ply" {
            assetURL = try cook(ply: imported, packageFolder: packageFolder)
        } else {
            note("cook: skipped, \(imported.lastPathComponent) is already baked")
            assetURL = imported
        }
        let header = try UntoldGSFormat.readHeaderV3(from: assetURL)
        let finePayloadBytes = Int((header.coarseIndexOffset > 0 ? header.coarseIndexOffset : header.fileSize) - header.payloadOffset)
        note("asset: \(assetURL.lastPathComponent) file=\(gaussianFormatBytes(Int(header.fileSize))) splats=\(header.splatCount) chunks=\(header.chunkCount) (\(1 << Int(header.log2ChunkSplats))/chunk) sh=\(header.shDegree) (\(header.shBytesPerSplat) B/splat) finePayload=\(gaussianFormatBytes(finePayloadBytes)) packed=\(gaussianFormatBytes(GaussianPagingPolicy.assetBytes(splatCount: Int(header.splatCount), shBytesPerSplat: header.shBytesPerSplat))) coarseLevels=\(header.coarseLevelCount) ratios=\(Array(header.coarseRatioLog2.prefix(Int(header.coarseLevelCount)))) coarseRecords=\(header.coarseRecordCount) coarseBytes=\(gaussianFormatBytes(header.coarsePayloadOffset > 0 ? Int(header.fileSize - header.coarsePayloadOffset) : 0))")
        XCTAssertEqual(primaryGaussianAsset(in: packageFolder)?.resolvingSymlinksInPath().path, assetURL.resolvingSymlinksInPath().path, "the browser resolves the package to the baked file")

        // (c) Place through the drop / double-click call.
        let placement = try await place(asset: assetURL)
        note("placement: load \(ms(placement.loadSeconds)) (main thread free) firstFrame \(ms(placement.firstFrameSeconds)) bounds=\(placement.bounds.min) … \(placement.bounds.max)")
        note("path: \(placement.path.description)")

        // (d) Render with the twin preview on, then off.
        let preview = try XCTUnwrap(twinPreview)
        preview.activate()
        preview.isEnabled = true
        XCTAssertNil(scene.get(component: GaussianTwinComponent.self, for: entity), "a plain entity never gets a twin")
        let suites = try runPoseSuites(bounds: placement.bounds, framesPerPose: framesPerPose, orbitFrames: orbitFrames, variants: [
            (label: "twins preview on", apply: { preview.isEnabled = true }),
            (label: "twins preview off", apply: { preview.isEnabled = false }),
        ])
        let withTwins = suites[0]
        let withoutTwins = suites[1]
        assertSuitesMatch(withTwins, withoutTwins, paged: placement.path.isPaged)
        XCTAssertNil(scene.get(component: GaussianTwinComponent.self, for: entity))
        XCTAssertEqual(scene.get(component: GaussianComponent.self, for: entity)?.opacityScale, 1, "the preview leaves a plain entity's opacity alone")

        return CaptureOutcome(assetURL: assetURL, header: header, path: placement.path, suites: [withTwins, withoutTwins])
    }

    /// The cook sheet's defaults through `cookGaussianPLY`, timed, with the process footprint
    /// before and the lifetime peak after.
    private func cook(ply: URL, packageFolder: URL) throws -> URL {
        let settings = GaussianCookSettings()
        let sourceCount = try PLYReader.readGaussianSplatCount(from: ply)
        let before = Self.footprint()
        let start = CACurrentMediaTime()
        let result = try cookGaussianPLY(plyURL: ply, settings: settings, outputDirectory: packageFolder)
        let seconds = CACurrentMediaTime() - start
        let after = Self.footprint()
        XCTAssertEqual(result.tiers.count, settings.levelCount, "the sheet's default tier count")
        let tier = try XCTUnwrap(result.tiers.first)
        let coarse = tier.coarseReport.map { "levels=\($0.levelCount) ratios=\($0.ratioLog2) recordsPerLevel=\($0.recordsPerLevel) bytes=\(gaussianFormatBytes($0.bytes)) chunksWithoutLevels=\($0.chunksWithoutLevels)" } ?? "none"
        note("cook: \(sourceCount) source splats -> \(tier.url.lastPathComponent) in \(String(format: "%.1f", seconds)) s; kept \(result.cookReport.keptSplatCount) of \(result.cookReport.inputSplatCount) (pruned: opacity \(result.cookReport.prunedByOpacity), degenerate \(result.cookReport.prunedByDegenerateGeometry), crop \(result.cookReport.prunedByCrop), budget \(result.cookReport.prunedByBudget); sh \(result.cookReport.shDegree)); settings: tiers \(settings.levelCount), sh \(settings.shDegree.map(String.init) ?? "source"), \(settings.chunkSplats)/chunk, budget \(settings.cookOptions.maxSplatCount.map(String.init) ?? "unlimited"), coarse .automatic -> \(coarse)")
        note("cook memory: footprint before \(gaussianFormatBytes(before.current)) after \(gaussianFormatBytes(after.current)) lifetime peak \(gaussianFormatBytes(after.peak)) (peak delta over before \(gaussianFormatBytes(max(0, after.peak - before.current))))")
        return tier.url
    }

    /// `loadEditorGaussianAuto` as the drop / double-click path calls it, waited for, then the
    /// first frame timed on its own.
    private func place(asset: URL) async throws -> Placement {
        if entity == .invalid || !scene.exists(entity) {
            entity = createEntity()
            setEntityName(entityId: entity, name: asset.deletingPathExtension().lastPathComponent)
        }
        let loaded = expectation(description: "loadEditorGaussianAuto \(asset.lastPathComponent)")
        var succeeded = false
        let start = CACurrentMediaTime()
        let accepted = loadEditorGaussianAuto(entityId: entity, url: asset) { success in
            succeeded = success
            loaded.fulfill()
        }
        XCTAssertTrue(accepted, "the editor accepts \(asset.lastPathComponent)")
        await fulfillment(of: [loaded], timeout: 900)
        let loadSeconds = CACurrentMediaTime() - start
        XCTAssertTrue(succeeded, "the load reported success")
        // The placement is a Tasks-panel job: it finishes with the engine path the file takes.
        for _ in 0 ..< 5 {
            await Task.yield()
        }
        let loadTask = TaskCenter.shared.tasks.last { $0.title == "Loading \(asset.lastPathComponent)" }
        XCTAssertEqual(loadTask?.state, .succeeded, "the placement task succeeded")
        if asset.pathExtension.lowercased() == "untoldgs" {
            let expected = try GaussianRuntimeSummary.read(url: asset).placementDetail
            XCTAssertEqual(loadTask?.detail, expected, "the task row carries the runtime summary")
        }
        note("placement task: \(loadTask?.detail ?? "none")")
        let component = try XCTUnwrap(scene.get(component: GaussianComponent.self, for: entity), "the entity carries a GaussianComponent")
        let metadata = try XCTUnwrap(EditorGaussianAssetState.shared.metadata(for: entity), "the editor tracks the placed asset")
        XCTAssertEqual(metadata.sourceURL, asset)

        var path = EnginePath()
        path.isChunked = component.isChunked
        path.isPaged = component.isPaged
        path.hasCoarse = component.chunkTable?.hasCoarse ?? false
        path.coarseLevels = component.chunkTable?.coarse?.levelCount ?? 0
        path.chunkCount = component.chunkTable?.chunkCount ?? 0
        path.splatCount = Int(component.splatCount)
        path.residentSplats = component.residentSplatCount
        path.estimatedGPUBytes = component.estimatedGPUBytes
        path.poolBytes = component.pager?.stats.poolBytes ?? 0
        path.slotCount = component.pager?.stats.slotCount ?? 0
        path.progressiveLevels = metadata.progressiveLevelCount
        path.loadingMode = metadata.loadingMode.rawValue
        XCTAssertTrue(component.hasResidentSplats)
        if component.encodedSplatData != nil {
            note("WARNING: the entity took the whole-buffer path (encodedSplatData), not the chunk path")
        }

        let bounds = component.localBoundingBox ?? (min: simd_float3(repeating: -1), max: simd_float3(repeating: 1))
        placeCamera(eye: bounds.max + (bounds.max - bounds.min), target: (bounds.min + bounds.max) / 2, bounds: bounds)
        let firstFrameStart = CACurrentMediaTime()
        let first = try drawFrame(component: component)
        let firstFrameSeconds = CACurrentMediaTime() - firstFrameStart
        XCTAssertTrue(first.completed, "the first frame after placement completes")
        return Placement(path: path, bounds: bounds, loadSeconds: loadSeconds, firstFrameSeconds: firstFrameSeconds)
    }

    // MARK: - Rendering

    struct FrameSample {
        var completed = false
        var cpuMs = 0.0
        var gpuMs = 0.0
        var visibleCount = 0
        var overflowCount = 0
        var capacity = 0
        var workingSetBytes = 0
        var state = GaussianBudgetState()
        var visibleChunks = 0
        var targetDensity: Float = 0
        var fullDensity: Float = 0
        var pager: GaussianPagingStats?
        var footprint = 0
    }

    struct PoseSummary {
        let name: String
        let frames: Int
        let gpuMean: Double
        let gpuMedian: Double
        let gpuMax: Double
        let cpuMean: Double
        let cpuMax: Double
        let last: FrameSample
        let coarseChunkShareMean: Double
        let coarseSplatShareMean: Double
        let issued: Int
        let committed: Int
        let evicted: Int
        let footprintMax: Int
    }

    struct PoseSuite {
        let label: String
        let poses: [PoseSummary]
    }

    private func poseDirection() -> simd_float3 {
        simd_normalize(simd_float3(0.35, 0.3, 1))
    }

    private func placeCamera(eye: simd_float3, target: simd_float3, bounds: (min: simd_float3, max: simd_float3)) {
        if cameraEntity == .invalid || !scene.exists(cameraEntity) {
            cameraEntity = createEntity()
            setEntityName(entityId: cameraEntity, name: "Large capture camera")
            if let cameraComponent = scene.assign(to: cameraEntity, component: CameraComponent.self) {
                cameraComponent.viewSpace = matrix_identity_float4x4
                cameraComponent.localPosition = .zero
            }
        }
        CameraSystem.shared.activeCamera = cameraEntity
        // The far plane reaches past the whole capture from the far pose.
        let radius = simd_length(bounds.max - bounds.min) / 2
        let wantedFar = max(savedFar, radius * 8)
        if far != wantedFar {
            far = wantedFar
            renderer.mtkView(renderer.metalView, drawableSizeWillChange: CGSize(width: viewportWidth, height: viewportHeight))
            renderer.pendingResize = false
        }
        cameraLookAt(entityId: cameraEntity, eye: eye, target: target, up: simd_float3(0, 1, 0))
    }

    /// One renderer frame, waited for, with the frame's readbacks.
    private func drawFrame(component: GaussianComponent) throws -> FrameSample {
        var sample = FrameSample()
        let cpuStart = CACurrentMediaTime()
        renderer.draw(in: renderer.metalView)
        sample.cpuMs = (CACurrentMediaTime() - cpuStart) * 1000
        let commandBuffer: MTLCommandBuffer? = renderInfo.lastCommandBuffer
        commandBuffer?.waitUntilCompleted()
        sample.completed = commandBuffer?.status == .completed
        if let commandBuffer, commandBuffer.gpuEndTime > 0 {
            sample.gpuMs = (commandBuffer.gpuEndTime - commandBuffer.gpuStartTime) * 1000
        }
        let slot = min(renderInfo.currentInFlightFrameSlot, maxInFlightCommandBuffers - 1)
        let workingSet = GaussianSharedWorkingSet.shared
        if let visible = workingSet.visibleSet(slot: slot)?.contents().load(as: GaussianVisibleSet.self) {
            sample.visibleCount = Int(visible.visibleCount)
            sample.overflowCount = Int(visible.overflowCount)
        }
        sample.capacity = workingSet.capacity
        sample.workingSetBytes = workingSet.residentBytes
        if let state = workingSet.budgetReadback(slot: slot)?.contents().load(as: GaussianBudgetState.self) {
            sample.state = state
        }
        if let histogram = workingSet.densityReadback(slot: slot)?.contents().load(as: GaussianBudgetDensityHistogram.self) {
            sample.visibleChunks = Int(histogram.visibleChunks)
            sample.targetDensity = histogram.targetDensity
            sample.fullDensity = histogram.fullDensity
        }
        sample.pager = component.pager?.stats
        sample.footprint = Self.footprint().current
        return sample
    }

    /// The per-frame invariants: the frame completed and dropped nothing, the pager has no
    /// fault and holds no more than its pool, and the grant fits the budget (with the headroom
    /// on a truncated frame).
    private func assertFrameInvariants(_ sample: FrameSample, pose: String, frame: Int, file: StaticString = #filePath, line: UInt = #line) {
        let context = "\(pose) frame \(frame)"
        XCTAssertTrue(sample.completed, "\(context): the command buffer completed", file: file, line: line)
        XCTAssertEqual(sample.overflowCount, 0, "\(context): no splat was dropped by arrival order", file: file, line: line)
        XCTAssertLessThanOrEqual(sample.visibleCount, sample.capacity, "\(context): the set holds no more than its capacity", file: file, line: line)
        let state = sample.state
        let grant = Int(state.quotaSplats) + Int(state.reservedSplats)
        XCTAssertLessThanOrEqual(grant, Int(state.budget), "\(context): the grant fits the budget", file: file, line: line)
        if state.targetScale < 1 {
            XCTAssertLessThanOrEqual(grant, max(Int(Float(state.budget) * gaussianBudgetHeadroom), Int(state.reservedSplats)), "\(context): a truncated frame leaves the headroom", file: file, line: line)
        }
        if let pager = sample.pager {
            XCTAssertEqual(pager.faultedChunks, 0, "\(context): no faulted chunk", file: file, line: line)
            XCTAssertEqual(pager.corruptChunks, 0, "\(context): no corrupt chunk", file: file, line: line)
            XCTAssertEqual(pager.state, .active, "\(context): the pager is active", file: file, line: line)
            XCTAssertFalse(pager.coarseFaulted, "\(context): the coarse levels did not fault", file: file, line: line)
            XCTAssertLessThanOrEqual(pager.residentSlots, pager.slotCount, "\(context): resident slots fit the pool", file: file, line: line)
        }
    }

    /// Frames until the pager has nothing pending and issues nothing for a few frames in a row
    /// (a whole-resident entity settles at once), so a measured pose starts from the residency
    /// the camera asks for rather than from whatever the previous pose left. Returns the frames
    /// it took, capped.
    @discardableResult
    private func settlePager(component: GaussianComponent, maxFrames: Int = 900) throws -> Int {
        guard component.pager != nil else { return 0 }
        var quiet = 0
        var frames = 0
        while frames < maxFrames, quiet < 5 {
            let sample = try drawFrame(component: component)
            frames += 1
            if let pager = sample.pager, pager.pendingReads == 0, pager.issuedThisTick == 0, pager.committedThisTick == 0 {
                quiet += 1
            } else {
                quiet = 0
            }
        }
        return frames
    }

    private func renderPose(name: String, frames: Int, eye: (Int) -> simd_float3, target: simd_float3, bounds: (min: simd_float3, max: simd_float3), settled: Int? = nil) throws -> PoseSummary {
        let component = try XCTUnwrap(scene.get(component: GaussianComponent.self, for: entity))
        var samples: [FrameSample] = []
        samples.reserveCapacity(frames)
        var issued = 0, committed = 0, evicted = 0
        var coarseChunkShare = 0.0, coarseSplatShare = 0.0
        for frame in 0 ..< frames {
            placeCamera(eye: eye(frame), target: target, bounds: bounds)
            let isLast = frame == frames - 1
            if isLast {
                // The engine's own profile line for the pose's last frame.
                if Logger.logLevel.rawValue < LogLevel.info.rawValue { Logger.logLevel = .info }
                Logger.enable(category: .gaussian)
            }
            let sample = try drawFrame(component: component)
            if isLast {
                Logger.set(category: .gaussian, enabled: savedGaussianLog)
                Logger.logLevel = savedLogLevel
            }
            assertFrameInvariants(sample, pose: name, frame: frame)
            if let pager = sample.pager {
                issued += pager.issuedThisTick
                committed += pager.committedThisTick
                evicted += pager.evictedThisTick
            }
            if sample.visibleChunks > 0 {
                coarseChunkShare += Double(sample.state.coarseChunks) / Double(sample.visibleChunks)
            }
            if sample.state.quotaSplats > 0 {
                coarseSplatShare += Double(sample.state.coarseSplats) / Double(sample.state.quotaSplats)
            }
            samples.append(sample)
        }
        let gpu = samples.map(\.gpuMs).sorted()
        let cpu = samples.map(\.cpuMs)
        let summary = PoseSummary(
            name: name,
            frames: frames,
            gpuMean: gpu.reduce(0, +) / Double(max(1, gpu.count)),
            gpuMedian: gpu.isEmpty ? 0 : gpu[gpu.count / 2],
            gpuMax: gpu.last ?? 0,
            cpuMean: cpu.reduce(0, +) / Double(max(1, cpu.count)),
            cpuMax: cpu.max() ?? 0,
            last: samples.last ?? FrameSample(),
            coarseChunkShareMean: coarseChunkShare / Double(max(1, frames)),
            coarseSplatShareMean: coarseSplatShare / Double(max(1, frames)),
            issued: issued,
            committed: committed,
            evicted: evicted,
            footprintMax: samples.map(\.footprint).max() ?? 0
        )
        note(describe(summary) + (settled.map { " | settled in \($0) frames before measuring" } ?? ""))
        return summary
    }

    /// Near (the camera next to the capture), mid, far (the whole capture in view) and an orbit,
    /// once per variant. At each static pose the pager is settled once and every variant then
    /// measures the same residency back to back (nothing is issued during a settled pose), so
    /// variants differ by what they change, not by what the pager fetched in between; the orbit
    /// runs whole per variant.
    private func runPoseSuites(bounds: (min: simd_float3, max: simd_float3), framesPerPose: Int, orbitFrames: Int, variants: [(label: String, apply: () -> Void)]) throws -> [PoseSuite] {
        let component = try XCTUnwrap(scene.get(component: GaussianComponent.self, for: entity))
        let centre = (bounds.min + bounds.max) / 2
        let radius = max(simd_length(bounds.max - bounds.min) / 2, 0.01)
        let direction = poseDirection()
        var poses: [[PoseSummary]] = Array(repeating: [], count: variants.count)
        for (name, distance) in [("near", 0.15), ("mid", 1.0), ("far", 2.2)] as [(String, Float)] {
            let eye = centre + direction * (radius * distance)
            placeCamera(eye: eye, target: centre, bounds: bounds)
            let settled = try settlePager(component: component)
            for (index, variant) in variants.enumerated() {
                variant.apply()
                note("-- \(name), \(variant.label) --")
                try poses[index].append(renderPose(name: name, frames: framesPerPose, eye: { _ in eye }, target: centre, bounds: bounds, settled: component.pager != nil ? settled : nil))
            }
        }
        let orbitHeight = centre.y + radius * 0.3
        for (index, variant) in variants.enumerated() {
            variant.apply()
            note("-- orbit, \(variant.label) --")
            try poses[index].append(renderPose(name: "orbit", frames: orbitFrames, eye: { frame in
                let angle = Float(frame) / Float(max(1, orbitFrames)) * 2 * .pi
                return simd_float3(centre.x + radius * cos(angle), orbitHeight, centre.z + radius * sin(angle))
            }, target: centre, bounds: bounds))
        }
        return variants.enumerated().map { PoseSuite(label: $0.element.label, poses: poses[$0.offset]) }
    }

    /// A plain entity draws the same with the preview on and off: the same visible splats and
    /// grant at every static pose (exactly for a whole-resident entity; a paged one measures the
    /// same settled residency both ways but its level cross-fades and the budget hysteresis may
    /// still differ by a frame, so within 2 %).
    private func assertSuitesMatch(_ a: PoseSuite, _ b: PoseSuite, paged: Bool) {
        for (x, y) in zip(a.poses, b.poses) where x.name != "orbit" {
            let tolerance = paged ? max(1, Int(Double(x.last.visibleCount) * 0.02)) : 0
            XCTAssertLessThanOrEqual(abs(x.last.visibleCount - y.last.visibleCount), tolerance, "\(x.name): the preview changes nothing for a plain entity (visible \(x.last.visibleCount) vs \(y.last.visibleCount))")
            XCTAssertLessThanOrEqual(abs(Int(x.last.state.quotaSplats) - Int(y.last.state.quotaSplats)), tolerance, "\(x.name): the preview changes nothing for a plain entity (quota \(x.last.state.quotaSplats) vs \(y.last.state.quotaSplats))")
            XCTAssertEqual(x.last.state.reservedSplats, y.last.state.reservedSplats, "\(x.name): no whole-buffer reservation either way")
        }
    }

    // MARK: - Report

    private func describe(_ pose: PoseSummary) -> String {
        let last = pose.last
        let state = last.state
        let timing = String(format: "%@: %d frames gpuMs mean %.2f median %.2f max %.2f | cpuMs mean %.2f max %.2f",
                            pose.name, pose.frames, pose.gpuMean, pose.gpuMedian, pose.gpuMax, pose.cpuMean, pose.cpuMax)
        let set = String(format: " | visible %d/%d workingSet %@", last.visibleCount, last.capacity, gaussianFormatBytes(last.workingSetBytes))
        let densityCap = state.densityCap.isFinite ? String(format: "%.4g", state.densityCap) : "inf"
        let budget = String(format: " | requested %d quota %d reserved %d budget %d scale %.3f target %.3f densityCap %@ visibleChunks %d",
                            Int(state.requestedSplats), Int(state.quotaSplats), Int(state.reservedSplats), Int(state.budget), state.scale, state.targetScale, densityCap, last.visibleChunks)
        let levels = String(format: " | levels: coarseChunks %d (%.1f%% of chunks over the pose) coarseSplats %d (%.1f%% of the quota) transition %d",
                            Int(state.coarseChunks), pose.coarseChunkShareMean * 100, Int(state.coarseSplats), pose.coarseSplatShareMean * 100, Int(state.transitionSplats))
        var line = timing + set + budget + levels + " | footprint max \(gaussianFormatBytes(pose.footprintMax))"
        if let pager = last.pager {
            let slotBytes = pager.slotCount > 0 ? pager.poolBytes / pager.slotCount : 0
            let pool = String(format: " | paging: pool %@ resident %@ (%d/%d slots) chunks %d resident %d whole, pending %d inFlight %@",
                              gaussianFormatBytes(pager.poolBytes), gaussianFormatBytes(pager.residentSlots * slotBytes), pager.residentSlots, pager.slotCount,
                              pager.residentChunks, pager.wholeChunks, pager.pendingReads, gaussianFormatBytes(pager.bytesInFlight))
            let traffic = String(format: ", over the pose issued %d committed %d evicted %d, saturated %d faults %d corrupt %d state %@ tick %d",
                                 pose.issued, pose.committed, pose.evicted, pager.saturatedCandidates, pager.faultedChunks, pager.corruptChunks, "\(pager.state)", Int(pager.tick))
            let coarse = String(format: " | coarse: levels %d bytes %@ landed %@ chunkLevels %d reads %d",
                                pager.coarseLevels, gaussianFormatBytes(pager.coarseBytes), gaussianFormatBytes(pager.coarseBytesLanded), pager.coarseChunkLevelsAvailable, pager.coarseReadsIssued)
            line += pool + traffic + coarse
        } else {
            line += " | paging: none (whole-resident)"
        }
        return line
    }

    private func reportDelta(baseline: PoseSuite, variant: PoseSuite) {
        note("-- A/B deltas (\(variant.label) minus \(baseline.label)) --")
        for (a, b) in zip(baseline.poses, variant.poses) {
            let timing = String(format: "%@: gpuMs mean %+.2f (%.2f -> %.2f) median %+.2f max %+.2f | cpuMs mean %+.2f",
                                a.name, b.gpuMean - a.gpuMean, a.gpuMean, b.gpuMean, b.gpuMedian - a.gpuMedian, b.gpuMax - a.gpuMax, b.cpuMean - a.cpuMean)
            let counts = String(format: " | visible %+d (%d -> %d) | workingSet %+d B", b.last.visibleCount - a.last.visibleCount, a.last.visibleCount, b.last.visibleCount, b.last.workingSetBytes - a.last.workingSetBytes)
            let memory = String(format: " | footprint max %+.1f MiB (%@ -> %@) | pool %@ -> %@",
                                Double(b.footprintMax - a.footprintMax) / 1_048_576, gaussianFormatBytes(a.footprintMax), gaussianFormatBytes(b.footprintMax),
                                gaussianFormatBytes(a.last.pager?.poolBytes ?? 0), gaussianFormatBytes(b.last.pager?.poolBytes ?? 0))
            note(timing + counts + memory)
        }
    }

    private func note(_ line: String) {
        report.append(line)
    }

    private func printReport() {
        print("[LargeCapture] ---- report ----")
        for line in report {
            print("[LargeCapture] \(line)")
        }
        print("[LargeCapture] ---- end ----")
    }

    private func ms(_ seconds: Double) -> String {
        String(format: "%.1f ms", seconds * 1000)
    }

    private func fileSize(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }

    /// The process's physical footprint now and its lifetime peak (`proc_pid_rusage`).
    private static func footprint() -> (current: Int, peak: Int) {
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) { pointer -> Int32 in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        guard status == 0 else { return (0, 0) }
        return (Int(info.ri_phys_footprint), Int(info.ri_lifetime_max_phys_footprint))
    }

    // MARK: - Fixture

    /// The 200-splat ASCII grid the cook-sheet tests use.
    static func makeFixturePLY(splatCount: Int) -> Data {
        var body = ""
        for index in 0 ..< splatCount {
            let x = Float(index % 10) * 0.1
            let y = Float(index / 10 % 10) * 0.1
            let z = Float(index / 100) * 0.1
            body += "\(x) \(y) \(z) 0 0 1 0.2 0.1 -0.1 2.0 -4 -4 -4 1 0 0 0\n"
        }
        let header = """
        ply
        format ascii 1.0
        element vertex \(splatCount)
        property float x
        property float y
        property float z
        property float nx
        property float ny
        property float nz
        property float f_dc_0
        property float f_dc_1
        property float f_dc_2
        property float opacity
        property float scale_0
        property float scale_1
        property float scale_2
        property float rot_0
        property float rot_1
        property float rot_2
        property float rot_3
        end_header
        """
        return Data((header + "\n" + body).utf8)
    }
}
