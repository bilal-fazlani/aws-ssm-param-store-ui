# Graph Feature — Design Spec

**Date:** 2026-05-11
**Status:** Draft, awaiting user review
**Owner:** @bilal-fazlani

## 1. Goal

Provide a sheet-based, interactive graph view that lets the user **see all parameters of an active connection at once**, arranged radially around a central "home" node representing the connection. The primary value is *seeing everything together at scale* — not navigation efficiency.

## 2. Scope

**In scope (v1):**
- Sheet presentation triggered from the main window (toolbar button + ⌘G), available only when a connection is active.
- Force-directed layout (SpriteKit physics simulation) of all parameters and intermediate folders for the active connection.
- Pan/zoom camera, hover labels, click selection, double-click navigation, per-folder collapse/expand.
- Toolbar: close, search, fit-to-view, reset zoom, SVG export.
- Mini-map overlay.
- Cluster coloring by top-level folder.
- Right-click context menus (folder: Expand / Collapse / View in Explorer; leaf: View in Explorer).
- Light/dark theme support.
- SVG export of the current view.

**Out of scope (v1):**
- Live updates while the sheet is open (snapshot-on-open model).
- Drag-to-pin / manual node positioning.
- Pause/resume of physics (auto-freeze on settle is sufficient).
- Type-based filtering (String / SecureString / StringList).
- VoiceOver navigation of the graph itself (toolbar controls remain accessible).
- PNG export.
- Right-click on empty canvas.
- Persistence of camera state, collapsed-folder state, or layout positions across sheet opens.

## 3. User Flows

### 3.1 Opening the graph
1. User has an active connection. The "Graph" toolbar button (and `View → Show Graph`, ⌘G) become enabled.
2. User invokes either. A sheet opens (~1200×800, resizable).
3. Snapshot of `appState.rootNodes` is taken; `GraphScene` instantiates one sprite per `ConfigNode` and one edge per parent→child relation.
4. Initial positions are randomized in a small radius around the anchored home node. Physics runs. A subtle "Arranging…" pill appears for ~2-3 seconds while the layout settles.
5. Once kinetic energy drops below threshold for N consecutive frames, `physicsWorld.speed` is set to 0 (auto-freeze).

### 3.2 Exploring
- Two-finger drag (or click-drag empty canvas) → pan camera.
- Pinch / scroll wheel → zoom (clamped 0.1× – 4×). The point under the cursor stays under the cursor during zoom.
- Hover a node → floating label appears above it showing the full path; the node itself dims slightly.
- ⤢ Fit-to-view (⌘1) → animate camera to fit all visible nodes (300ms ease).
- ⟲ Reset (⌘0) → animate camera to home node at 1× zoom.

### 3.3 Selecting a node
- Single click on a node → set `selectedNodeId`; draw a blue glow ring around it; dim unrelated nodes to 50% opacity; show the info card at bottom-center.
- Single click on empty canvas → deselect, clear card, restore opacity.
- Info card shows: full path, value (masked appropriately for SecureString display rules already used in the app), type, version, "updated X ago", and an "Open ↗" button.

### 3.4 Navigating to a node
- Double-click a leaf → close the sheet, set `appState.selectedNodeId` to that leaf, main detail view opens it.
- "Open ↗" button on info card → same as double-click.
- Right-click leaf → "View in Explorer" → same as double-click.
- Right-click folder → "View in Explorer" → close sheet and reveal the folder in the sidebar (selected and scrolled into view, expanded).

### 3.5 Collapsing / expanding folders
- `GraphViewModel.collapsedFolderIds: Set<String>` (set of `ConfigNode.id`, which is the full path) is the source of truth.
- Double-click a folder, or right-click → Expand / Collapse, calls `viewModel.toggleCollapse(folderId:)`.
- On collapse: descendants' sprites, edges, and physics bodies are removed from the scene. The folder shows a `+N` badge where N is the count of hidden descendants (computed from the model tree).
- On expand: descendants are re-instantiated and re-joined. Physics resumes briefly to settle the new bodies, then auto-freezes again.

### 3.6 Searching
- Toolbar search field. Substring match against full path, case-insensitive.
- Matching nodes: full opacity + cyan ring. Non-matching: dim to 15%.
- Empty search: restore full opacity.
- ↵ in the search field: animate camera to fit the bounding rect of the matching set.

### 3.7 Exporting SVG
- Toolbar `↓ SVG` opens `NSSavePanel` with default filename `<connection-name>-<YYYYMMDD-HHmmss>.svg`.
- `GraphSVGExporter` walks the current scene state, emits `<circle>` per visible node, `<line>` per visible edge, `<text>` per label, plus the home-node icon. Uses the current camera transform — what you see is what you save.

## 4. Architecture

### 4.1 New files
All under `AWSSSMParamStoreUI/Views/Graph/`:

| File | Type | Responsibility |
|------|------|----------------|
| `GraphSheet.swift` | SwiftUI `View` | Root sheet view. ZStack of `SpriteView` + toolbar + info card + mini-map. Owns `GraphViewModel`. |
| `GraphViewModel.swift` | `@MainActor ObservableObject` | UI state: `selectedNodeId`, `searchText`, `collapsedFolderIds`, `cameraTransform`, `hoveredNodeId`. Builds initial graph from `appState.rootNodes`. |
| `GraphScene.swift` | `SKScene` | The SpriteKit world. Owns `SKCameraNode`, physics simulation, all node/edge sprites. Handles mouse events. |
| `GraphNodeSprite.swift` | `SKNode` subclass | One per `ConfigNode`. Holds circle, label, badge, selection ring, physics body. Knows its `ConfigNode.id`. |
| `GraphEdge.swift` | `SKShapeNode` | One line per parent→child relation. Re-pathed each tick. |
| `MiniMapView.swift` | SwiftUI `View` | Bottom-right overview with viewport rectangle. |
| `GraphInfoCard.swift` | SwiftUI `View` | Bottom-center panel for the selected node. |
| `GraphSVGExporter.swift` | struct | Walks the scene, produces an SVG document. |
| `GraphTheme.swift` | struct | Color palette responsive to `colorScheme`. Cluster palette: 8 fixed hues cycled by top-level folder index. |

### 4.2 Touched files

| File | Change |
|------|--------|
| `Views/ContentView.swift` | Add toolbar button "Graph" (disabled when `appState.currentConnection == nil` or `!appState.isConnected`); wire `.sheet(isPresented:)`. |
| `AWSSSMParamStoreUIApp.swift` | Add `View → Show Graph` menu command bound to ⌘G with the same disabled rule. |

No changes to `AppState`, `ConfigNode`, `SSMService`, or any data layer. The graph is a pure read-only visualization built from a snapshot of the existing tree.

### 4.3 Snapshot model
The sheet is modal. While open, the user cannot mutate the tree from the main UI (existing modal-overlay locking already enforces this — see commit 0017e82). Therefore the graph snapshots `rootNodes` at sheet-open and discards everything at sheet-close. No live diffing required.

## 5. Physics

- **Repulsion:** each node has an `SKPhysicsBody.circle(radius:)`. Bodies in the same `categoryBitMask` collide → natural overlap avoidance.
- **Attraction:** each parent→child edge installs an `SKPhysicsJointSpring` between the two bodies, with frequency and damping tuned so springs settle without oscillating.
- **Centering:** a single `SKFieldNode.radialGravityField` at origin with mild strength keeps the cluster anchored.
- **Damping:** `physicsBody.linearDamping = 0.9` per node.
- **Gravity:** `physicsWorld.gravity = .zero`.
- **Home node:** `isDynamic = false`, fixed at origin.
- **Auto-freeze:** in `update(_:)`, sample total kinetic energy. After 30 consecutive frames below threshold, set `physicsWorld.speed = 0`. Resumes when collapse/expand or other structural changes happen.
- **LOD in `update(_:)`:** label visibility tied to `camera.xScale`. Hidden < 0.5×, shown ≥ 0.5×. Hover label always shown regardless of zoom.

For 1500 nodes, SpriteKit's spatial broad-phase handles collision detection efficiently. Initial settle time target: ≤ 3 seconds on M-series Macs.

## 6. Toolbar

Final layout:

`[✕]  |  [🔍 search…]  |  [⤢ Fit (⌘1)]  [⟲ Reset (⌘0)]  [↓ SVG]`

No pause control. No type filter. No right-click on empty canvas.

## 7. Edge cases & polish

- **Empty connection (zero params):** show "No parameters in this connection" placeholder centered in the sheet; no canvas.
- **Single param:** physics still runs; one leaf orbits the home node. Looks fine.
- **Connection with very deep paths:** depth doesn't matter for layout (force-directed); only total node count does.
- **Window resize while sheet is open:** SpriteView resizes; camera viewport adjusts; layout untouched.
- **Light/dark mode toggle while open:** `GraphTheme` observes `colorScheme`, repaints sprite colors on change.
- **Physics setup failure:** unlikely, but fall back to static radial layout (single ring) and show a non-blocking warning toast.
- **Older Intel Macs:** if needed, lower default LOD threshold (hide labels at < 0.7× zoom) and consider gating high node counts behind a perf warning. Defer measurement until Intel testing.

## 8. Accessibility

- Toolbar controls, search field, info card, and "Open ↗" button: standard SwiftUI accessibility, no extra work.
- Graph canvas itself: **not** VoiceOver-navigable in v1. Documented limitation. Users needing screen-reader access continue to use the existing sidebar/detail view.
- Keyboard alternative for search: ⌘F focuses the search field. Future: arrow-key cycling through matches.

## 9. Testing strategy

- **Unit tests:** `GraphViewModel` snapshot construction (tree → flat list with cluster ids); `collapsedFolderIds` toggle behavior; SVG exporter output shape.
- **Manual / visual:** open sheet against connections of varying sizes (10, 100, 500, 1500 params); verify settle time, collapse/expand correctness, search highlighting, double-click navigation, SVG export round-trip.
- **No CI tests for SpriteKit physics behavior** — visual regression testing is out of scope; visual review during PR is sufficient.

## 10. Open questions

None outstanding. All product decisions resolved during brainstorm.

## 11. Decision log

| Decision | Choice | Reason |
|----------|--------|--------|
| Layout algorithm | Force-directed (organic) | User wants the "alive" feel; clusters emerge from data. |
| Rendering tech | SpriteKit (SKScene in SpriteView) | Best balance of performance (1500 nodes) and native feel. |
| Data scope | Show everything | Stated user goal: see all params at scale. |
| Click behavior | Click highlights, double-click navigates | Graph is for exploration; jumping out should be deliberate. |
| Drag-to-pin | Dropped | User confirmed not needed. |
| Pause control | Dropped | Auto-freeze on settle is sufficient. |
| Type filter | Dropped | User removed during review. |
| Right-click empty canvas | None | User: not needed. |
| Live AppState reactivity | None (snapshot model) | Sheet is modal; no mutations possible while open. |
| Persistence (camera, collapse state, layout) | None across opens | Keeps v1 simple; revisit if users ask. |
| VoiceOver in graph canvas | Deferred | Significant SpriteKit a11y work; sidebar covers the gap. |
