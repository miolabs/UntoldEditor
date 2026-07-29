# Untold Engine Editor — UI Overhaul

Summary of changes, restructurings and fixes.

## Theme & colors

- Expanded **`EditorScheme.swift`** from 7 to ~23 semantic tokens: text hierarchy (primary/secondary/tertiary/inverse), status (error/success/warning/info in Dracula tones), fills/dividers and overlays/shadows.
- Migrated ~240 hardcoded colors across 15 views to those tokens.
- Added reusable helpers: **`editorPanel()`** (card look) and **`EditorDisclosureStyle`** (chevron-width indentation).

## Dark appearance & window

- Forced dark mode (`preferredColorScheme(.dark)` + `NSWindow` `.darkAqua`) — fixed invisible black text over dark backgrounds.
- Transparent title bar and window background tinted with the theme color (was black).

## Top toolbar → native macOS menu

- Removed the top toolbar (New/Open/Reset/Play/Save/FPS).
- Built the native menu (App / File / View) in `main.swift`, bridged via notifications (`EditorMenuCommands.swift`).
- **Shortcut fix:** the engine's `keyDown` monitor was eating all keys; now ⌘ combos pass through to the menu.

## Right panel — contextual

- Removed the Environment/Effects/Inspector `TabView`.
- Project selected → **Environment/Effects** (themed segmented); Scene selected → **scene inspector**; Object selected → **Inspector**.
- Uniform `editorPanel()` styling, 5px content inset, 5px card margin; content top-aligned.
- Fixed card misalignment when expanding a `DisclosureGroup` (native AA segmented → themed control + `EditorDisclosureStyle`); removed the blue leaf icon; toggles now label-left / switch-right.
- Sliders and switches tinted orange (selected state); action buttons (Add IBL, Assign) made neutral — orange now means *selected* only (reverted a global tint that turned every button orange).

## Panel show / hide

- Toggles in the View menu (⌘1 / ⌘2 / ⌘3) plus ⌘F (Focus Viewport, restores the previous layout).
- Edge tabs on each panel that protrude over the viewport (`zIndex`).
- Animated show/hide with the render loop paused during the animation.

## Performance / async loading

- Render paused during window live-resize.
- Hierarchy refreshes when async loading finishes (tiles/streaming): detects the falling edge of `AssetLoadingGate` in `EditorSceneView.didDraw` → notification (replaced the polling patch).

## Assets panel — Finder-style redesign

- Removed the toolbar (Import/Load Authored/Delete) and the "Target Entity" row.
- Split view: directory tree on the left (project root node + categories + subfolders), folder contents on the right.
- Right-click: empty area → Import / Import Remote Stream / Load Authored; item → Delete; folder → New Directory. Import targets the selected folder.
- Search moved to the top (shared with the console); left split widened 25%.

## Bottom panel (Assets / Console)

- Native tab strip → themed segmented control.
- Shared search in the bar (filters assets or console depending on the tab).
- Console lost its internal header; Auto-scroll + Clear moved to the bar (Console only); the log fills the area.

## Viewport

- Move/Rotate/Scale cluster moved to the top-center; fixed hit area (`contentShape`) and themed active color.

## Files

- **New:** `EditorMenuCommands.swift`, `ProjectSceneCatalog.swift`.
- **To remove:** `ToolbarView.swift` (left empty) → `git rm`.

## Keyboard shortcuts

New shortcuts wired through the native menu bar:

| Shortcut | Action | Menu |
|----------|--------|------|
| ⌘N | New project | File |
| ⌘O | Open project | File |
| ⇧⌘N | Add new scene | File |
| ⌘S | Save scene | File |
| ⇧⌘S | Save scene as… | File |
| ⌘1 | Toggle left panel (Scene Graph) | View |
| ⌘2 | Toggle bottom panel (Assets / Console) | View |
| ⌘3 | Toggle right panel (Inspector) | View |
| ⌘F | Focus viewport (hide all panels / restore) | View |
| ⌘Q | Quit | App |

> **Note:** Save Project has no shortcut (avoids clashing with ⌘S for Save Scene). Undo/redo (⌘Z / ⇧⌘Z) are handled by the engine's editor undo manager.

## Project > Scenes restructuring

### What was restructured

The left panel changed from a flat entity list into a three-level tree: **Project → Scenes → elements**.

- The **project** is a fixed header (folder + name), non-collapsible, carrying the Play/Pause button and acting as a selectable node that drives the Environment/Effects editors on the right.
- **Scenes** are listed from a new `ProjectSceneCatalog`, which scans the project's `Scenes/` folder for `.untoldscene` files. Because the engine keeps a single scene loaded at a time, only the **active** scene expands to show live ECS elements; the others are file references. Clicking a non-active scene loads it (replacing the world) after a confirmation.
- The active scene is **selectable** (shows a scene inspector on the right) with an independent expand chevron and a "+" add menu.
- **Elements** are the live entities, collapsed by default, with icons matching their type, chevron-width indentation, and right-click Add (nests under the node) / Delete / Unparent.
- Selection state lives in `SelectionManager` (`projectSelected` / `sceneSelected` / entity), mutually exclusive.
- "Add New Scene" resets the world to a fresh, unsaved scene; the catalog auto-refreshes on save and on load.

### What's left to do

- **Real multi-scene** is not possible yet — `loadScene` calls `destroyAllEntities()`, so only one scene is live. Several scenes at once (or additive loading) needs engine work: tagging entities by scene and load/unload per scene.
- **Dirty tracking:** the "unsaved changes" confirmation on scene switch always fires because there's no modified flag. Hook a dirty state (e.g. via the undo manager) so it only warns on real changes.
- **Scene inspector is a placeholder** — only name and path. Define and implement real per-scene properties (environment/effects per scene, default camera, streaming settings…).
- **Scene management from the tree:** no rename / duplicate / delete of scene files yet, only load and "Add New Scene". Add a right-click menu on scene rows (Rename / Duplicate / Delete / Reveal in Assets).
- **"Add New Scene" doesn't create a file** until Save As — it only resets the world. Consider creating a `.untoldscene` file immediately and adding it to the catalog.
- **Save Project** is a placeholder (saves the active scene) because the engine has no project file/config. Define what a project persists (settings, scene list, active scene) and implement a real project manifest.
- **Catalog freshness:** refreshes on save/appear/load but not on external filesystem changes. A folder watcher or a manual refresh action would close that gap.
- **Non-active scene UX:** clicking loads immediately; a thumbnail/preview or a distinct "open" affordance would make it clearer.
