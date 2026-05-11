# Graph Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a sheet-based, force-directed graph view (SpriteKit) of all parameters of the active connection, with search, mini-map, cluster coloring, per-folder collapse/expand, and SVG export.

**Architecture:** New `Views/Graph/` subfolder containing one SwiftUI sheet (`GraphSheet`) that hosts an `SKScene` (`GraphScene`) inside a `ZStack` with SwiftUI overlays (toolbar, info card, mini-map). A `GraphViewModel` (`@MainActor ObservableObject`) holds UI state and a snapshot of `appState.rootNodes`. SpriteKit's physics handles repulsion (collisions), attraction (`SKPhysicsJointSpring`), and centering (`SKFieldNode.radialGravityField`). No changes to data layer.

**Tech Stack:** Swift 5.9+, SwiftUI, SpriteKit (`SpriteView`, `SKScene`, `SKCameraNode`, `SKPhysicsBody`, `SKFieldNode`), AppKit bridges (`NSTrackingArea`, `NSEvent`, `NSMenu`, `NSSavePanel`), Swift Testing framework (`import Testing`).

**Spec:** `docs/superpowers/specs/2026-05-11-graph-feature-design.md`

**Test command (used throughout):**
```
xcodebuild test -scheme AWSSSMParamStoreUI -destination 'platform=macOS' \
  -only-testing:AWSSSMParamStoreUITests/<SuiteName>/<test_name> 2>&1 \
  | grep -E "Test Suite|Test Case|passed|failed|error:"
```

**Build check command (used after every UI task):**
```
xcodebuild -scheme AWSSSMParamStoreUI -destination 'platform=macOS' build 2>&1 \
  | grep -E "(error:|warning:|Build succeeded|Build FAILED)"
```

---

## Pre-flight: Add files to Xcode project

> **Note:** This is a Swift project using `.xcodeproj`. New `.swift` files added to disk also need to be added to the `AWSSSMParamStoreUI` Xcode target via the project file. After creating each new file in this plan, drag it into the Xcode project navigator (or use `xcodeproj` CLI), assign it to the `AWSSSMParamStoreUI` target, and verify the next build picks it up. Test files go in the `AWSSSMParamStoreUITests` target.

---

## Task 1: GraphTheme

Builds a small color palette struct that is `colorScheme`-aware and provides cluster colors deterministically by index.

**Files:**
- Create: `AWSSSMParamStoreUI/Views/Graph/GraphTheme.swift`
- Create: `AWSSSMParamStoreUITests/GraphThemeTests.swift`

- [ ] **Step 1: Write the failing test**

Create `AWSSSMParamStoreUITests/GraphThemeTests.swift`:

```swift
import Testing
import SwiftUI
@testable import AWSSSMParamStoreUI

@Suite struct GraphThemeTests {
    @Test func cluster_color_is_deterministic_by_index() {
        let theme = GraphTheme(colorScheme: .dark)
        #expect(theme.clusterColor(forIndex: 0) == theme.clusterColor(forIndex: 0))
        #expect(theme.clusterColor(forIndex: 0) != theme.clusterColor(forIndex: 1))
    }

    @Test func cluster_palette_has_eight_hues_and_cycles() {
        let theme = GraphTheme(colorScheme: .dark)
        // Index 8 wraps to index 0
        #expect(theme.clusterColor(forIndex: 8) == theme.clusterColor(forIndex: 0))
        #expect(theme.clusterColor(forIndex: 9) == theme.clusterColor(forIndex: 1))
    }

    @Test func home_color_differs_between_light_and_dark() {
        let dark = GraphTheme(colorScheme: .dark)
        let light = GraphTheme(colorScheme: .light)
        // Both must be defined; we don't assert equality, only that both exist.
        _ = dark.homeNodeColor
        _ = light.homeNodeColor
        #expect(dark.canvasBackground != light.canvasBackground)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```
xcodebuild test -scheme AWSSSMParamStoreUI -destination 'platform=macOS' \
  -only-testing:AWSSSMParamStoreUITests/GraphThemeTests 2>&1 | grep -E "error:|failed"
```
Expected: compile error "cannot find 'GraphTheme' in scope".

- [ ] **Step 3: Implement GraphTheme**

Create `AWSSSMParamStoreUI/Views/Graph/GraphTheme.swift`:

```swift
import SwiftUI
import AppKit

struct GraphTheme: Equatable {
    let colorScheme: ColorScheme

    var canvasBackground: NSColor {
        colorScheme == .dark ? NSColor(white: 0.08, alpha: 1) : NSColor(white: 0.97, alpha: 1)
    }

    var homeNodeColor: NSColor { NSColor.systemGreen }

    var edgeColor: NSColor {
        colorScheme == .dark
            ? NSColor.white.withAlphaComponent(0.18)
            : NSColor.black.withAlphaComponent(0.18)
    }

    var labelColor: NSColor {
        colorScheme == .dark ? .white : .black
    }

    var labelBackground: NSColor {
        colorScheme == .dark
            ? NSColor.black.withAlphaComponent(0.85)
            : NSColor.white.withAlphaComponent(0.92)
    }

    var selectionRingColor: NSColor { NSColor.systemBlue }

    var searchHighlightRingColor: NSColor { NSColor.systemTeal }

    private static let clusterPalette: [NSColor] = [
        NSColor.systemOrange,
        NSColor.systemPink,
        NSColor.systemPurple,
        NSColor.systemTeal,
        NSColor.systemIndigo,
        NSColor.systemYellow,
        NSColor.systemMint,
        NSColor.systemRed
    ]

    func clusterColor(forIndex index: Int) -> NSColor {
        Self.clusterPalette[((index % Self.clusterPalette.count) + Self.clusterPalette.count) % Self.clusterPalette.count]
    }
}
```

- [ ] **Step 4: Add the file to the Xcode `AWSSSMParamStoreUI` target and the test file to `AWSSSMParamStoreUITests` target. Re-run the test command.**

Expected: `Test Suite 'GraphThemeTests' passed`.

- [ ] **Step 5: Commit**

```
git add AWSSSMParamStoreUI/Views/Graph/GraphTheme.swift \
        AWSSSMParamStoreUITests/GraphThemeTests.swift \
        AWSSSMParamStoreUI.xcodeproj/project.pbxproj
git commit -m "Add GraphTheme color palette for graph feature"
```

---

## Task 2: GraphSnapshot model and builder

Pure value type representing a flattened tree (used by both view model and SpriteKit scene). One function to build it from `[ConfigNode]`. Fully unit-testable, no UI.

**Files:**
- Create: `AWSSSMParamStoreUI/Views/Graph/GraphSnapshot.swift`
- Create: `AWSSSMParamStoreUITests/GraphSnapshotTests.swift`

- [ ] **Step 1: Write the failing test**

Create `AWSSSMParamStoreUITests/GraphSnapshotTests.swift`:

```swift
import Testing
@testable import AWSSSMParamStoreUI

@Suite struct GraphSnapshotTests {
    private func makeTree() -> [ConfigNode] {
        // Builds two top-level folders /app1 and /app2 each with one leaf
        // /app1/db (folder) -> /app1/db/host (leaf)
        // /app2/key (leaf)
        ConfigNode.buildTree(from: [
            (path: "/app1/db/host", value: "h", type: "String", lastModified: nil, description: nil),
            (path: "/app2/key", value: "k", type: "SecureString", lastModified: nil, description: nil)
        ])
    }

    @Test func builds_flat_node_list_with_home_and_all_descendants() {
        let snap = GraphSnapshot.build(from: makeTree(), connectionName: "prod")
        // 1 home + 2 top folders + 1 nested folder + 2 leaves = 6
        #expect(snap.nodes.count == 6)
        #expect(snap.nodes.first(where: { $0.kind == .home })?.label == "prod")
    }

    @Test func produces_one_edge_per_parent_child_relation() {
        let snap = GraphSnapshot.build(from: makeTree(), connectionName: "prod")
        // home->/app1, home->/app2, /app1->/app1/db, /app1/db->/app1/db/host, /app2->/app2/key = 5
        #expect(snap.edges.count == 5)
    }

    @Test func assigns_cluster_index_by_top_level_folder() {
        let snap = GraphSnapshot.build(from: makeTree(), connectionName: "prod")
        let app1Cluster = snap.nodes.first(where: { $0.fullPath == "/app1" })?.clusterIndex
        let app2Cluster = snap.nodes.first(where: { $0.fullPath == "/app2" })?.clusterIndex
        let nestedCluster = snap.nodes.first(where: { $0.fullPath == "/app1/db/host" })?.clusterIndex
        #expect(app1Cluster != nil)
        #expect(app2Cluster != nil)
        #expect(app1Cluster != app2Cluster)
        #expect(nestedCluster == app1Cluster, "descendants inherit top-level cluster index")
    }

    @Test func home_node_has_cluster_index_negative_one() {
        let snap = GraphSnapshot.build(from: makeTree(), connectionName: "prod")
        let home = snap.nodes.first(where: { $0.kind == .home })!
        #expect(home.clusterIndex == -1)
        #expect(home.parentId == nil)
    }

    @Test func empty_tree_produces_only_home_node() {
        let snap = GraphSnapshot.build(from: [], connectionName: "dev")
        #expect(snap.nodes.count == 1)
        #expect(snap.nodes[0].kind == .home)
        #expect(snap.edges.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```
xcodebuild test -scheme AWSSSMParamStoreUI -destination 'platform=macOS' \
  -only-testing:AWSSSMParamStoreUITests/GraphSnapshotTests 2>&1 | grep -E "error:|failed"
```
Expected: compile error on `GraphSnapshot`.

- [ ] **Step 3: Implement GraphSnapshot**

Create `AWSSSMParamStoreUI/Views/Graph/GraphSnapshot.swift`:

```swift
import Foundation

struct GraphSnapshot: Equatable {
    enum NodeKind: Equatable { case home, folder, leaf }

    struct Node: Equatable, Identifiable {
        let id: String          // "__home__" for home; ConfigNode.fullPath otherwise
        let kind: NodeKind
        let label: String       // last path segment, or connection name for home
        let fullPath: String    // "" for home; ConfigNode.fullPath otherwise
        let parentId: String?
        let clusterIndex: Int   // -1 for home; same for all nodes under same top-level folder
        let type: String?       // String / StringList / SecureString (leaves only)
    }

    struct Edge: Equatable {
        let fromId: String
        let toId: String
    }

    static let homeId = "__home__"

    let nodes: [Node]
    let edges: [Edge]

    static func build(from rootNodes: [ConfigNode], connectionName: String) -> GraphSnapshot {
        var nodes: [Node] = [
            Node(id: homeId, kind: .home, label: connectionName, fullPath: "",
                 parentId: nil, clusterIndex: -1, type: nil)
        ]
        var edges: [Edge] = []

        for (clusterIndex, top) in rootNodes.enumerated() {
            walk(node: top, parentId: homeId, clusterIndex: clusterIndex,
                 nodes: &nodes, edges: &edges)
        }
        return GraphSnapshot(nodes: nodes, edges: edges)
    }

    private static func walk(node: ConfigNode, parentId: String, clusterIndex: Int,
                             nodes: inout [Node], edges: inout [Edge]) {
        nodes.append(Node(
            id: node.id,
            kind: node.isLeaf ? .leaf : .folder,
            label: node.name,
            fullPath: node.fullPath,
            parentId: parentId,
            clusterIndex: clusterIndex,
            type: node.type
        ))
        edges.append(Edge(fromId: parentId, toId: node.id))
        for child in node.children ?? [] {
            walk(node: child, parentId: node.id, clusterIndex: clusterIndex,
                 nodes: &nodes, edges: &edges)
        }
    }
}
```

- [ ] **Step 4: Add files to Xcode targets, re-run test**

Expected: `GraphSnapshotTests` passes (5 tests).

- [ ] **Step 5: Commit**

```
git add AWSSSMParamStoreUI/Views/Graph/GraphSnapshot.swift \
        AWSSSMParamStoreUITests/GraphSnapshotTests.swift \
        AWSSSMParamStoreUI.xcodeproj/project.pbxproj
git commit -m "Add GraphSnapshot for flat tree representation"
```

---

## Task 3: GraphViewModel — collapse/expand logic

Holds UI state. Tested through pure logic (no SwiftUI needed). Computes the visible subset of snapshot nodes/edges given a `collapsedFolderIds` set.

**Files:**
- Create: `AWSSSMParamStoreUI/Views/Graph/GraphViewModel.swift`
- Create: `AWSSSMParamStoreUITests/GraphViewModelTests.swift`

- [ ] **Step 1: Write the failing test**

Create `AWSSSMParamStoreUITests/GraphViewModelTests.swift`:

```swift
import Testing
@testable import AWSSSMParamStoreUI

@Suite @MainActor struct GraphViewModelTests {
    private func makeViewModel() -> GraphViewModel {
        let tree = ConfigNode.buildTree(from: [
            (path: "/app1/db/host", value: "h", type: "String", lastModified: nil, description: nil),
            (path: "/app1/db/port", value: "p", type: "String", lastModified: nil, description: nil),
            (path: "/app2/key", value: "k", type: "SecureString", lastModified: nil, description: nil)
        ])
        let vm = GraphViewModel()
        vm.load(rootNodes: tree, connectionName: "prod")
        return vm
    }

    @Test func default_visible_set_includes_all_snapshot_nodes() {
        let vm = makeViewModel()
        // 1 home + /app1 + /app1/db + /app1/db/host + /app1/db/port + /app2 + /app2/key = 7
        #expect(vm.visibleNodes.count == 7)
        #expect(vm.visibleEdges.count == 6)
    }

    @Test func collapsing_folder_hides_descendants_and_their_edges() {
        let vm = makeViewModel()
        vm.toggleCollapse(folderId: "/app1/db")
        // /app1/db itself stays visible; /app1/db/host and /app1/db/port hidden.
        #expect(vm.visibleNodes.contains(where: { $0.id == "/app1/db" }))
        #expect(!vm.visibleNodes.contains(where: { $0.id == "/app1/db/host" }))
        #expect(!vm.visibleNodes.contains(where: { $0.id == "/app1/db/port" }))
        // The two edges into the hidden leaves are also hidden.
        #expect(vm.visibleEdges.count == 4)
    }

    @Test func hidden_descendant_count_for_collapsed_folder() {
        let vm = makeViewModel()
        vm.toggleCollapse(folderId: "/app1/db")
        #expect(vm.hiddenDescendantCount(forFolderId: "/app1/db") == 2)
    }

    @Test func toggle_twice_restores_visibility() {
        let vm = makeViewModel()
        vm.toggleCollapse(folderId: "/app1/db")
        vm.toggleCollapse(folderId: "/app1/db")
        #expect(vm.visibleNodes.count == 7)
        #expect(vm.visibleEdges.count == 6)
    }

    @Test func collapsing_top_level_folder_hides_whole_subtree() {
        let vm = makeViewModel()
        vm.toggleCollapse(folderId: "/app1")
        // /app1 visible; /app1/db, /app1/db/host, /app1/db/port hidden.
        #expect(vm.visibleNodes.count == 4) // home + /app1 + /app2 + /app2/key
        #expect(vm.hiddenDescendantCount(forFolderId: "/app1") == 3)
    }
}
```

- [ ] **Step 2: Run test, expect compile error**

```
xcodebuild test -scheme AWSSSMParamStoreUI -destination 'platform=macOS' \
  -only-testing:AWSSSMParamStoreUITests/GraphViewModelTests 2>&1 | grep -E "error:|failed"
```
Expected: "cannot find 'GraphViewModel' in scope".

- [ ] **Step 3: Implement GraphViewModel (collapse/expand only — search comes in Task 4)**

Create `AWSSSMParamStoreUI/Views/Graph/GraphViewModel.swift`:

```swift
import Foundation
import SwiftUI

@MainActor
final class GraphViewModel: ObservableObject {
    @Published private(set) var snapshot: GraphSnapshot = GraphSnapshot(nodes: [], edges: [])
    @Published var collapsedFolderIds: Set<String> = []
    @Published var selectedNodeId: String?
    @Published var hoveredNodeId: String?
    @Published var searchText: String = ""

    func load(rootNodes: [ConfigNode], connectionName: String) {
        snapshot = GraphSnapshot.build(from: rootNodes, connectionName: connectionName)
        collapsedFolderIds = []
        selectedNodeId = nil
        hoveredNodeId = nil
        searchText = ""
    }

    func toggleCollapse(folderId: String) {
        if collapsedFolderIds.contains(folderId) {
            collapsedFolderIds.remove(folderId)
        } else {
            collapsedFolderIds.insert(folderId)
        }
    }

    /// IDs of nodes that are inside (transitively) any collapsed folder.
    private var hiddenNodeIds: Set<String> {
        guard !collapsedFolderIds.isEmpty else { return [] }
        let parentToChildren: [String: [String]] = Dictionary(
            grouping: snapshot.edges, by: { $0.fromId }
        ).mapValues { $0.map(\.toId) }

        var hidden: Set<String> = []
        var queue: [String] = []
        for collapsed in collapsedFolderIds {
            queue.append(contentsOf: parentToChildren[collapsed] ?? [])
        }
        while let next = queue.popLast() {
            if hidden.insert(next).inserted {
                queue.append(contentsOf: parentToChildren[next] ?? [])
            }
        }
        return hidden
    }

    var visibleNodes: [GraphSnapshot.Node] {
        let hidden = hiddenNodeIds
        return snapshot.nodes.filter { !hidden.contains($0.id) }
    }

    var visibleEdges: [GraphSnapshot.Edge] {
        let hidden = hiddenNodeIds
        return snapshot.edges.filter { !hidden.contains($0.fromId) && !hidden.contains($0.toId) }
    }

    func hiddenDescendantCount(forFolderId folderId: String) -> Int {
        guard collapsedFolderIds.contains(folderId) else { return 0 }
        let parentToChildren: [String: [String]] = Dictionary(
            grouping: snapshot.edges, by: { $0.fromId }
        ).mapValues { $0.map(\.toId) }
        var count = 0
        var queue = parentToChildren[folderId] ?? []
        while let next = queue.popLast() {
            count += 1
            queue.append(contentsOf: parentToChildren[next] ?? [])
        }
        return count
    }
}
```

- [ ] **Step 4: Add files to Xcode targets, re-run tests**

Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```
git add AWSSSMParamStoreUI/Views/Graph/GraphViewModel.swift \
        AWSSSMParamStoreUITests/GraphViewModelTests.swift \
        AWSSSMParamStoreUI.xcodeproj/project.pbxproj
git commit -m "Add GraphViewModel with collapse/expand logic"
```

---

## Task 4: GraphViewModel — search

Adds substring matching against full path; returns set of matching node ids.

**Files:**
- Modify: `AWSSSMParamStoreUI/Views/Graph/GraphViewModel.swift`
- Modify: `AWSSSMParamStoreUITests/GraphViewModelTests.swift`

- [ ] **Step 1: Append failing tests**

Add to `GraphViewModelTests.swift` inside the existing suite:

```swift
@Test func empty_search_text_returns_empty_match_set() {
    let vm = makeViewModel()
    vm.searchText = ""
    #expect(vm.matchingNodeIds.isEmpty)
}

@Test func search_substring_matches_full_path_case_insensitively() {
    let vm = makeViewModel()
    vm.searchText = "DB"
    let matches = vm.matchingNodeIds
    #expect(matches.contains("/app1/db"))
    #expect(matches.contains("/app1/db/host"))
    #expect(matches.contains("/app1/db/port"))
    #expect(!matches.contains("/app2/key"))
}

@Test func search_does_not_match_home_node() {
    let vm = makeViewModel()
    vm.searchText = "prod"
    // Even though connection name is "prod", we don't match home.
    #expect(!vm.matchingNodeIds.contains(GraphSnapshot.homeId))
}
```

- [ ] **Step 2: Run, expect compile failure on `matchingNodeIds`**

```
xcodebuild test -scheme AWSSSMParamStoreUI -destination 'platform=macOS' \
  -only-testing:AWSSSMParamStoreUITests/GraphViewModelTests 2>&1 | grep -E "error:|failed"
```

- [ ] **Step 3: Implement `matchingNodeIds`**

Add to `GraphViewModel`:

```swift
/// IDs of snapshot nodes whose full path contains `searchText` (case-insensitive).
/// Empty when `searchText` is empty. Excludes the synthetic home node.
var matchingNodeIds: Set<String> {
    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }
    let needle = trimmed.lowercased()
    var matches: Set<String> = []
    for node in snapshot.nodes where node.kind != .home {
        if node.fullPath.lowercased().contains(needle) {
            matches.insert(node.id)
        }
    }
    return matches
}
```

- [ ] **Step 4: Re-run tests, expect 8 total passing**

- [ ] **Step 5: Commit**

```
git add AWSSSMParamStoreUI/Views/Graph/GraphViewModel.swift \
        AWSSSMParamStoreUITests/GraphViewModelTests.swift
git commit -m "Add search matching to GraphViewModel"
```

---

## Task 5: GraphSVGExporter

Pure function: `(visible nodes with positions, visible edges, theme) -> SVG string`. Position is supplied by caller (we pass current sprite positions later).

**Files:**
- Create: `AWSSSMParamStoreUI/Views/Graph/GraphSVGExporter.swift`
- Create: `AWSSSMParamStoreUITests/GraphSVGExporterTests.swift`

- [ ] **Step 1: Write failing test**

Create `AWSSSMParamStoreUITests/GraphSVGExporterTests.swift`:

```swift
import Testing
@testable import AWSSSMParamStoreUI

@Suite struct GraphSVGExporterTests {
    @Test func exports_well_formed_svg_with_circle_per_node_and_line_per_edge() {
        let nodes: [GraphSVGExporter.PositionedNode] = [
            .init(id: "a", x: 0, y: 0, radius: 18, fillHex: "#10b981", label: "home"),
            .init(id: "b", x: 100, y: 0, radius: 12, fillHex: "#f59e0b", label: "/app1")
        ]
        let edges: [GraphSVGExporter.PositionedEdge] = [
            .init(x1: 0, y1: 0, x2: 100, y2: 0)
        ]
        let svg = GraphSVGExporter.export(nodes: nodes, edges: edges,
                                          edgeColorHex: "#888888",
                                          backgroundHex: "#141414")

        #expect(svg.hasPrefix("<?xml"))
        #expect(svg.contains("<svg"))
        #expect(svg.contains("</svg>"))
        // 2 circles
        #expect(svg.components(separatedBy: "<circle ").count - 1 == 2)
        // 1 line
        #expect(svg.components(separatedBy: "<line ").count - 1 == 1)
        // labels rendered as <text>
        #expect(svg.contains(">/app1<"))
        #expect(svg.contains("fill=\"#10b981\""))
        #expect(svg.contains("fill=\"#141414\""))
    }

    @Test func empty_input_produces_valid_empty_svg() {
        let svg = GraphSVGExporter.export(nodes: [], edges: [],
                                          edgeColorHex: "#888888",
                                          backgroundHex: "#ffffff")
        #expect(svg.contains("<svg"))
        #expect(svg.contains("</svg>"))
        #expect(!svg.contains("<circle"))
        #expect(!svg.contains("<line"))
    }
}
```

- [ ] **Step 2: Run, expect compile failure**

- [ ] **Step 3: Implement exporter**

Create `AWSSSMParamStoreUI/Views/Graph/GraphSVGExporter.swift`:

```swift
import Foundation

enum GraphSVGExporter {
    struct PositionedNode {
        let id: String
        let x: Double
        let y: Double
        let radius: Double
        let fillHex: String
        let label: String
    }

    struct PositionedEdge {
        let x1: Double
        let y1: Double
        let x2: Double
        let y2: Double
    }

    static func export(nodes: [PositionedNode],
                       edges: [PositionedEdge],
                       edgeColorHex: String,
                       backgroundHex: String) -> String {
        // Compute viewBox from node bounds plus a margin.
        let margin: Double = 60
        let xs = nodes.map(\.x); let ys = nodes.map(\.y)
        let minX = (xs.min() ?? 0) - margin
        let minY = (ys.min() ?? 0) - margin
        let width = ((xs.max() ?? 0) - (xs.min() ?? 0)) + 2 * margin
        let height = ((ys.max() ?? 0) - (ys.min() ?? 0)) + 2 * margin

        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        out += "<svg xmlns=\"http://www.w3.org/2000/svg\" "
        out += "viewBox=\"\(minX) \(minY) \(width) \(height)\" "
        out += "width=\"\(width)\" height=\"\(height)\">\n"
        out += "<rect x=\"\(minX)\" y=\"\(minY)\" width=\"\(width)\" height=\"\(height)\" fill=\"\(backgroundHex)\"/>\n"

        for e in edges {
            out += "<line x1=\"\(e.x1)\" y1=\"\(e.y1)\" x2=\"\(e.x2)\" y2=\"\(e.y2)\" "
            out += "stroke=\"\(edgeColorHex)\" stroke-width=\"1\"/>\n"
        }
        for n in nodes {
            out += "<circle cx=\"\(n.x)\" cy=\"\(n.y)\" r=\"\(n.radius)\" fill=\"\(n.fillHex)\"/>\n"
            let escaped = escapeXML(n.label)
            out += "<text x=\"\(n.x)\" y=\"\(n.y - n.radius - 4)\" "
            out += "text-anchor=\"middle\" font-family=\"-apple-system, sans-serif\" "
            out += "font-size=\"10\" fill=\"\(edgeColorHex)\">\(escaped)</text>\n"
        }
        out += "</svg>\n"
        return out
    }

    private static func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
```

- [ ] **Step 4: Re-run, expect both tests pass**

- [ ] **Step 5: Commit**

```
git add AWSSSMParamStoreUI/Views/Graph/GraphSVGExporter.swift \
        AWSSSMParamStoreUITests/GraphSVGExporterTests.swift \
        AWSSSMParamStoreUI.xcodeproj/project.pbxproj
git commit -m "Add GraphSVGExporter for SVG output"
```

---

## Task 6: GraphNodeSprite

SpriteKit node subclass holding circle, label, badge, selection ring, and physics body. No automated test — manual visual check after Task 9.

**Files:**
- Create: `AWSSSMParamStoreUI/Views/Graph/GraphNodeSprite.swift`

- [ ] **Step 1: Implement GraphNodeSprite**

Create `AWSSSMParamStoreUI/Views/Graph/GraphNodeSprite.swift`:

```swift
import SpriteKit

final class GraphNodeSprite: SKNode {
    let snapshotNodeId: String
    let kind: GraphSnapshot.NodeKind
    let fullPath: String

    private let circle: SKShapeNode
    private let labelNode: SKLabelNode
    private let labelBackground: SKShapeNode
    private let selectionRing: SKShapeNode
    private var badgeNode: SKNode?

    init(snapshotNode: GraphSnapshot.Node, theme: GraphTheme) {
        self.snapshotNodeId = snapshotNode.id
        self.kind = snapshotNode.kind
        self.fullPath = snapshotNode.fullPath

        let radius = Self.radius(for: snapshotNode.kind)
        circle = SKShapeNode(circleOfRadius: radius)
        circle.fillColor = Self.color(for: snapshotNode, theme: theme)
        circle.strokeColor = .white.withAlphaComponent(0.35)
        circle.lineWidth = 1.5

        labelNode = SKLabelNode(fontNamed: "SFMono-Regular")
        labelNode.fontSize = 9
        labelNode.fontColor = theme.labelColor
        labelNode.text = snapshotNode.label
        labelNode.verticalAlignmentMode = .center
        labelNode.horizontalAlignmentMode = .center
        labelNode.position = CGPoint(x: 0, y: radius + 12)

        let labelSize = labelNode.calculateAccumulatedFrame().size.applying(CGAffineTransform(scaleX: 1, y: 1))
        labelBackground = SKShapeNode(rectOf: CGSize(width: labelSize.width + 8, height: labelSize.height + 4),
                                      cornerRadius: 3)
        labelBackground.fillColor = theme.labelBackground
        labelBackground.strokeColor = .clear
        labelBackground.position = labelNode.position
        labelBackground.zPosition = -1

        selectionRing = SKShapeNode(circleOfRadius: radius + 4)
        selectionRing.strokeColor = theme.selectionRingColor
        selectionRing.lineWidth = 2.5
        selectionRing.fillColor = .clear
        selectionRing.glowWidth = 4
        selectionRing.isHidden = true

        super.init()

        addChild(selectionRing)
        addChild(circle)
        // labels added but hidden until hover/zoom
        addChild(labelBackground)
        addChild(labelNode)
        labelNode.isHidden = true
        labelBackground.isHidden = true

        // Physics
        let body = SKPhysicsBody(circleOfRadius: radius)
        body.linearDamping = 0.9
        body.angularDamping = 0.9
        body.allowsRotation = false
        body.mass = snapshotNode.kind == .home ? 100 : 1
        body.isDynamic = snapshotNode.kind != .home
        body.restitution = 0.05
        body.friction = 0
        body.categoryBitMask = 0x1
        body.collisionBitMask = 0x1
        body.contactTestBitMask = 0
        physicsBody = body
        name = snapshotNode.id
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    static func radius(for kind: GraphSnapshot.NodeKind) -> CGFloat {
        switch kind {
        case .home: return 20
        case .folder: return 12
        case .leaf: return 7
        }
    }

    static func color(for node: GraphSnapshot.Node, theme: GraphTheme) -> NSColor {
        switch node.kind {
        case .home: return theme.homeNodeColor
        case .folder, .leaf:
            let base = theme.clusterColor(forIndex: node.clusterIndex)
            return node.kind == .leaf ? base.withAlphaComponent(0.8) : base
        }
    }

    func setSelected(_ selected: Bool) {
        selectionRing.isHidden = !selected
    }

    func setLabelVisible(_ visible: Bool) {
        labelNode.isHidden = !visible
        labelBackground.isHidden = !visible
    }

    func setDimmed(_ dimmed: Bool) {
        circle.alpha = dimmed ? 0.15 : 1
    }

    func setBadge(count: Int?, theme: GraphTheme) {
        badgeNode?.removeFromParent()
        badgeNode = nil
        guard let count = count, count > 0 else { return }

        let label = SKLabelNode(fontNamed: "SFMono-Bold")
        label.fontSize = 8
        label.fontColor = theme.searchHighlightRingColor
        label.text = "+\(count)"
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center

        let size = label.calculateAccumulatedFrame().size
        let bg = SKShapeNode(rectOf: CGSize(width: size.width + 8, height: size.height + 4),
                             cornerRadius: 8)
        bg.fillColor = NSColor.black.withAlphaComponent(0.85)
        bg.strokeColor = theme.searchHighlightRingColor
        bg.lineWidth = 1.5

        let group = SKNode()
        group.position = CGPoint(x: Self.radius(for: kind) - 2, y: Self.radius(for: kind) - 2)
        group.zPosition = 5
        group.addChild(bg)
        group.addChild(label)
        addChild(group)
        badgeNode = group
    }
}
```

- [ ] **Step 2: Add to Xcode target, build**

```
xcodebuild -scheme AWSSSMParamStoreUI -destination 'platform=macOS' build 2>&1 \
  | grep -E "(error:|Build succeeded|Build FAILED)"
```
Expected: `Build succeeded`.

- [ ] **Step 3: Commit**

```
git add AWSSSMParamStoreUI/Views/Graph/GraphNodeSprite.swift \
        AWSSSMParamStoreUI.xcodeproj/project.pbxproj
git commit -m "Add GraphNodeSprite SpriteKit node class"
```

---

## Task 7: GraphEdge

SKShapeNode subclass that re-paths a line between two `GraphNodeSprite`s each frame.

**Files:**
- Create: `AWSSSMParamStoreUI/Views/Graph/GraphEdge.swift`

- [ ] **Step 1: Implement GraphEdge**

Create `AWSSSMParamStoreUI/Views/Graph/GraphEdge.swift`:

```swift
import SpriteKit

final class GraphEdge: SKShapeNode {
    weak var fromNode: GraphNodeSprite?
    weak var toNode: GraphNodeSprite?

    init(from: GraphNodeSprite, to: GraphNodeSprite, theme: GraphTheme) {
        super.init()
        self.fromNode = from
        self.toNode = to
        strokeColor = theme.edgeColor
        lineWidth = 1
        zPosition = -10
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    func updatePath() {
        guard let from = fromNode, let to = toNode else { return }
        let path = CGMutablePath()
        path.move(to: from.position)
        path.addLine(to: to.position)
        self.path = path
    }
}
```

- [ ] **Step 2: Add to Xcode target, build**

Expected: `Build succeeded`.

- [ ] **Step 3: Commit**

```
git add AWSSSMParamStoreUI/Views/Graph/GraphEdge.swift \
        AWSSSMParamStoreUI.xcodeproj/project.pbxproj
git commit -m "Add GraphEdge sprite class"
```

---

## Task 8: GraphScene skeleton

`SKScene` with a camera, an empty container, physics world setup, and a placeholder home node positioned at origin. Verifies SpriteKit setup compiles and renders without populating the graph yet.

**Files:**
- Create: `AWSSSMParamStoreUI/Views/Graph/GraphScene.swift`

- [ ] **Step 1: Implement GraphScene skeleton**

Create `AWSSSMParamStoreUI/Views/Graph/GraphScene.swift`:

```swift
import SpriteKit
import SwiftUI

final class GraphScene: SKScene {
    var theme: GraphTheme = GraphTheme(colorScheme: .dark) {
        didSet { applyTheme() }
    }

    private let cameraNode = SKCameraNode()
    private let container = SKNode()
    private var nodeSprites: [String: GraphNodeSprite] = [:]
    private var edgeSprites: [GraphEdge] = []
    private var centerField: SKFieldNode!

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        physicsWorld.gravity = .zero
        backgroundColor = theme.canvasBackground

        addChild(container)
        addChild(cameraNode)
        camera = cameraNode

        centerField = SKFieldNode.radialGravityField()
        centerField.strength = -0.6 // negative = inward pull
        centerField.falloff = -1
        centerField.position = .zero
        centerField.categoryBitMask = 0x1
        addChild(centerField)
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    private func applyTheme() {
        backgroundColor = theme.canvasBackground
        for edge in edgeSprites { edge.strokeColor = theme.edgeColor }
        // Sprite recoloring requires a full rebuild; cheap because positions don't change.
        // Implemented in Task 22.
    }

    override func update(_ currentTime: TimeInterval) {
        for edge in edgeSprites {
            edge.updatePath()
        }
    }
}
```

- [ ] **Step 2: Add to Xcode target, build**

```
xcodebuild -scheme AWSSSMParamStoreUI -destination 'platform=macOS' build 2>&1 \
  | grep -E "(error:|Build succeeded|Build FAILED)"
```
Expected: `Build succeeded`.

- [ ] **Step 3: Commit**

```
git add AWSSSMParamStoreUI/Views/Graph/GraphScene.swift \
        AWSSSMParamStoreUI.xcodeproj/project.pbxproj
git commit -m "Add GraphScene skeleton with camera and physics setup"
```

---

## Task 9: GraphScene populates from snapshot

Reads from a `GraphViewModel`'s `visibleNodes` / `visibleEdges`, instantiates sprites, joints, and home anchor.

**Files:**
- Modify: `AWSSSMParamStoreUI/Views/Graph/GraphScene.swift`

- [ ] **Step 1: Add `populate` method and helpers**

Inside `GraphScene`, add:

```swift
weak var viewModel: GraphViewModel?

func populate(viewModel: GraphViewModel) {
    self.viewModel = viewModel
    rebuild()
}

private func clearAll() {
    for sprite in nodeSprites.values { sprite.removeFromParent() }
    for edge in edgeSprites { edge.removeFromParent() }
    physicsWorld.removeAllJoints()
    nodeSprites.removeAll()
    edgeSprites.removeAll()
}

private func rebuild() {
    guard let vm = viewModel else { return }
    clearAll()

    // Build sprites
    for node in vm.visibleNodes {
        let sprite = GraphNodeSprite(snapshotNode: node, theme: theme)
        // Random initial position around origin (home stays at origin via isDynamic = false)
        if node.kind == .home {
            sprite.position = .zero
        } else {
            let angle = Double.random(in: 0..<(2 * .pi))
            let r = Double.random(in: 60..<200)
            sprite.position = CGPoint(x: r * cos(angle), y: r * sin(angle))
        }
        // Apply collapsed-folder badge
        if node.kind == .folder {
            let count = vm.hiddenDescendantCount(forFolderId: node.id)
            sprite.setBadge(count: count > 0 ? count : nil, theme: theme)
        }
        container.addChild(sprite)
        nodeSprites[node.id] = sprite
    }

    // Build edges + spring joints
    for edge in vm.visibleEdges {
        guard let a = nodeSprites[edge.fromId], let b = nodeSprites[edge.toId] else { continue }
        let edgeSprite = GraphEdge(from: a, to: b, theme: theme)
        container.addChild(edgeSprite)
        edgeSprites.append(edgeSprite)

        if let bodyA = a.physicsBody, let bodyB = b.physicsBody {
            let joint = SKPhysicsJointSpring.joint(
                withBodyA: bodyA, bodyB: bodyB,
                anchorA: a.position, anchorB: b.position
            )
            joint.frequency = 1.5
            joint.damping = 1.2
            physicsWorld.add(joint)
        }
    }

    // Reset camera
    cameraNode.position = .zero
    cameraNode.setScale(1.0)
}
```

- [ ] **Step 2: Build**

```
xcodebuild -scheme AWSSSMParamStoreUI -destination 'platform=macOS' build 2>&1 \
  | grep -E "(error:|Build succeeded|Build FAILED)"
```
Expected: `Build succeeded`.

- [ ] **Step 3: Commit**

```
git add AWSSSMParamStoreUI/Views/Graph/GraphScene.swift
git commit -m "Populate GraphScene sprites and joints from view model"
```

---

## Task 10: Auto-freeze physics on settle

When kinetic energy drops below threshold for 30 frames, freeze. Resume on rebuild.

**Files:**
- Modify: `AWSSSMParamStoreUI/Views/Graph/GraphScene.swift`

- [ ] **Step 1: Add freeze logic**

Add properties and update `update(_:)`:

```swift
private var lowEnergyFrames: Int = 0
private let energyThreshold: CGFloat = 0.5
private let framesToFreeze: Int = 30

override func update(_ currentTime: TimeInterval) {
    for edge in edgeSprites { edge.updatePath() }

    // Auto-freeze when kinetic energy is low for sustained frames.
    guard physicsWorld.speed > 0 else { return }
    var energy: CGFloat = 0
    for sprite in nodeSprites.values {
        guard let v = sprite.physicsBody?.velocity else { continue }
        energy += v.dx * v.dx + v.dy * v.dy
    }
    if energy < energyThreshold {
        lowEnergyFrames += 1
        if lowEnergyFrames >= framesToFreeze {
            physicsWorld.speed = 0
        }
    } else {
        lowEnergyFrames = 0
    }
}
```

Update `rebuild()` to resume physics:
```swift
// at the bottom of rebuild():
physicsWorld.speed = 1
lowEnergyFrames = 0
```

- [ ] **Step 2: Build**

Expected: `Build succeeded`.

- [ ] **Step 3: Commit**

```
git add AWSSSMParamStoreUI/Views/Graph/GraphScene.swift
git commit -m "Auto-freeze physics on settle"
```

---

## Task 11: Camera pan/zoom

Mouse drag pans the camera; scroll wheel zooms with the cursor as focal point. Pinch is wired via the AppKit `magnify(with:)` event.

**Files:**
- Modify: `AWSSSMParamStoreUI/Views/Graph/GraphScene.swift`

- [ ] **Step 1: Add camera control**

Add to `GraphScene`:

```swift
private var dragLastPoint: CGPoint?

override func mouseDown(with event: NSEvent) {
    dragLastPoint = event.location(in: self)
    // Hit-testing for selection is added in Task 12.
}

override func mouseDragged(with event: NSEvent) {
    guard let last = dragLastPoint else { return }
    let now = event.location(in: self)
    let dx = now.x - last.x
    let dy = now.y - last.y
    cameraNode.position = CGPoint(x: cameraNode.position.x - dx,
                                  y: cameraNode.position.y - dy)
    dragLastPoint = now
}

override func mouseUp(with event: NSEvent) {
    dragLastPoint = nil
}

override func scrollWheel(with event: NSEvent) {
    let zoomFactor: CGFloat = 1 + CGFloat(event.deltaY) * 0.04
    applyZoom(zoomFactor, around: event.location(in: self))
}

override func magnify(with event: NSEvent) {
    let zoomFactor: CGFloat = 1 + event.magnification
    applyZoom(zoomFactor, around: event.location(in: self))
}

private func applyZoom(_ factor: CGFloat, around focal: CGPoint) {
    let oldScale = cameraNode.xScale
    let newScale = max(0.1, min(4.0, oldScale * factor))
    if newScale == oldScale { return }
    // Keep `focal` (in scene coords) under the cursor:
    // camera.position += (focal - camera.position) * (1 - newScale/oldScale)
    let dx = (focal.x - cameraNode.position.x) * (1 - newScale / oldScale)
    let dy = (focal.y - cameraNode.position.y) * (1 - newScale / oldScale)
    cameraNode.position.x += dx
    cameraNode.position.y += dy
    cameraNode.setScale(newScale)
    updateLabelLOD()
}

private func updateLabelLOD() {
    // In SKCameraNode, smaller xScale = zoomed IN. Show labels when zoomed in close enough to read.
    let zoomedIn = cameraNode.xScale < 0.6
    for sprite in nodeSprites.values where sprite.kind != .home {
        // Don't override hover label visibility — set only based on zoom for non-hovered nodes.
        if sprite.snapshotNodeId != viewModel?.hoveredNodeId {
            sprite.setLabelVisible(zoomedIn)
        }
    }
}
```

> **Note on zoom convention:** With `SKCameraNode`, `xScale = 0.5` means zoomed-IN to 2× (each scene point covers more screen pixels). Labels become readable when `xScale < 0.6` per spec §3.2 LOD.

Public helpers (also called from toolbar):

```swift
func fitToView(animated: Bool) {
    guard !nodeSprites.isEmpty else { return }
    var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
    var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
    for sprite in nodeSprites.values {
        minX = min(minX, sprite.position.x); minY = min(minY, sprite.position.y)
        maxX = max(maxX, sprite.position.x); maxY = max(maxY, sprite.position.y)
    }
    let pad: CGFloat = 60
    let w = (maxX - minX) + 2 * pad
    let h = (maxY - minY) + 2 * pad
    let viewSize = view?.bounds.size ?? size
    let scale = max(w / viewSize.width, h / viewSize.height, 0.1)
    let center = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
    let move = SKAction.move(to: center, duration: animated ? 0.3 : 0)
    let zoom = SKAction.scale(to: max(0.1, min(4.0, scale)), duration: animated ? 0.3 : 0)
    cameraNode.run(SKAction.group([move, zoom])) { [weak self] in self?.updateLabelLOD() }
}

func resetZoom(animated: Bool) {
    let move = SKAction.move(to: .zero, duration: animated ? 0.3 : 0)
    let zoom = SKAction.scale(to: 1.0, duration: animated ? 0.3 : 0)
    cameraNode.run(SKAction.group([move, zoom])) { [weak self] in self?.updateLabelLOD() }
}
```

- [ ] **Step 2: Build**

Expected: `Build succeeded`.

- [ ] **Step 3: Commit**

```
git add AWSSSMParamStoreUI/Views/Graph/GraphScene.swift
git commit -m "Add camera pan/zoom to GraphScene"
```

---

## Task 12: Hover and click selection

Single-click sets `viewModel.selectedNodeId`; clicking empty canvas clears it. Hover shows label on the hovered node. Selected node gets ring; non-selected dimmed when something is selected.

**Files:**
- Modify: `AWSSSMParamStoreUI/Views/Graph/GraphScene.swift`

- [ ] **Step 1: Replace `mouseDown` with hit-testing logic**

Replace existing `mouseDown(with:)`:

```swift
private var mouseDownPoint: CGPoint?
private var mouseDownTime: TimeInterval = 0

override func mouseDown(with event: NSEvent) {
    mouseDownPoint = event.location(in: self)
    mouseDownTime = event.timestamp
    dragLastPoint = event.location(in: self)
}

override func mouseUp(with event: NSEvent) {
    defer { dragLastPoint = nil; mouseDownPoint = nil }
    guard let down = mouseDownPoint else { return }
    let up = event.location(in: self)
    let dist = hypot(up.x - down.x, up.y - down.y)
    let elapsed = event.timestamp - mouseDownTime
    if dist < 4 && elapsed < 0.4 {
        // Treat as a click
        if event.clickCount >= 2 {
            handleDoubleClick(at: up)
        } else {
            handleSingleClick(at: up)
        }
    }
}

private func sprite(at point: CGPoint) -> GraphNodeSprite? {
    let hit = nodes(at: point).compactMap { node -> GraphNodeSprite? in
        var n: SKNode? = node
        while n != nil {
            if let g = n as? GraphNodeSprite { return g }
            n = n?.parent
        }
        return nil
    }
    return hit.first
}

private func handleSingleClick(at point: CGPoint) {
    guard let vm = viewModel else { return }
    if let sprite = sprite(at: point) {
        vm.selectedNodeId = sprite.snapshotNodeId
    } else {
        vm.selectedNodeId = nil
    }
    refreshSelectionVisuals()
}

private func handleDoubleClick(at point: CGPoint) {
    // Implemented in Task 13.
}

func refreshSelectionVisuals() {
    let selected = viewModel?.selectedNodeId
    let dimming = selected != nil
    for (id, sprite) in nodeSprites {
        sprite.setSelected(id == selected)
        sprite.setDimmed(dimming && id != selected)
    }
}
```

- [ ] **Step 2: Add hover support via NSTrackingArea**

Add to `GraphScene` (called from view in Task 18):

```swift
func handleMouseMoved(toScenePoint point: CGPoint) {
    guard let vm = viewModel else { return }
    let hovered = sprite(at: point)?.snapshotNodeId
    if hovered == vm.hoveredNodeId { return }
    if let prevId = vm.hoveredNodeId, let prev = nodeSprites[prevId], prev.kind != .home {
        // Restore based on LOD only
        prev.setLabelVisible(cameraNode.xScale < 0.6)
    }
    vm.hoveredNodeId = hovered
    if let id = hovered, let sprite = nodeSprites[id], sprite.kind != .home {
        sprite.setLabelVisible(true)
    }
}
```

- [ ] **Step 3: Build**

Expected: `Build succeeded`.

- [ ] **Step 4: Commit**

```
git add AWSSSMParamStoreUI/Views/Graph/GraphScene.swift
git commit -m "Add hover and click selection to GraphScene"
```

---

## Task 13: Double-click navigation and folder collapse/expand

Double-clicking a leaf closes the sheet and selects that leaf in `appState`. Double-clicking a folder toggles its collapse/expand and rebuilds the affected subtree.

**Files:**
- Modify: `AWSSSMParamStoreUI/Views/Graph/GraphScene.swift`

- [ ] **Step 1: Add navigation closure and double-click handler**

Add to `GraphScene`:

```swift
/// Called when user double-clicks a leaf. Caller closes the sheet and selects it in appState.
var onNavigateToLeaf: ((String) -> Void)?

private func handleDoubleClick(at point: CGPoint) {
    guard let sprite = sprite(at: point) else { return }
    switch sprite.kind {
    case .leaf:
        onNavigateToLeaf?(sprite.snapshotNodeId)
    case .folder:
        viewModel?.toggleCollapse(folderId: sprite.snapshotNodeId)
        rebuild()
    case .home:
        break
    }
}
```

- [ ] **Step 2: Build**

Expected: `Build succeeded`.

- [ ] **Step 3: Commit**

```
git add AWSSSMParamStoreUI/Views/Graph/GraphScene.swift
git commit -m "Wire double-click for leaf nav and folder collapse"
```

---

## Task 14: Right-click context menu

Right-click on folder → Expand / Collapse / View in Explorer. Right-click on leaf → View in Explorer. Right-click on empty canvas → no menu.

**Files:**
- Modify: `AWSSSMParamStoreUI/Views/Graph/GraphScene.swift`

- [ ] **Step 1: Add right-click handling**

Add to `GraphScene`:

```swift
/// Caller wires this to close the sheet and reveal the node in the sidebar.
var onRevealInExplorer: ((String) -> Void)?

override func rightMouseDown(with event: NSEvent) {
    let point = event.location(in: self)
    guard let sprite = sprite(at: point), let view = self.view else { return }
    let menu = NSMenu()
    switch sprite.kind {
    case .folder:
        let id = sprite.snapshotNodeId
        let isCollapsed = viewModel?.collapsedFolderIds.contains(id) == true
        let collapseExpand = NSMenuItem(
            title: isCollapsed ? "Expand" : "Collapse",
            action: #selector(menuToggleCollapse(_:)),
            keyEquivalent: ""
        )
        collapseExpand.target = self
        collapseExpand.representedObject = id
        menu.addItem(collapseExpand)
        menu.addItem(.separator())
        let reveal = NSMenuItem(title: "View in Explorer",
                                action: #selector(menuRevealInExplorer(_:)),
                                keyEquivalent: "")
        reveal.target = self
        reveal.representedObject = id
        menu.addItem(reveal)
    case .leaf:
        let reveal = NSMenuItem(title: "View in Explorer",
                                action: #selector(menuRevealInExplorer(_:)),
                                keyEquivalent: "")
        reveal.target = self
        reveal.representedObject = sprite.snapshotNodeId
        menu.addItem(reveal)
    case .home:
        return
    }
    NSMenu.popUpContextMenu(menu, with: event, for: view)
}

@objc private func menuToggleCollapse(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    viewModel?.toggleCollapse(folderId: id)
    rebuild()
}

@objc private func menuRevealInExplorer(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    onRevealInExplorer?(id)
}
```

- [ ] **Step 2: Build**

Expected: `Build succeeded`.

- [ ] **Step 3: Commit**

```
git add AWSSSMParamStoreUI/Views/Graph/GraphScene.swift
git commit -m "Add right-click context menu for graph nodes"
```

---

## Task 15: Search highlighting in scene

Reads `viewModel.matchingNodeIds`. Matching nodes get full opacity + cyan ring. Non-matching: dimmed to 15%.

**Files:**
- Modify: `AWSSSMParamStoreUI/Views/Graph/GraphNodeSprite.swift`
- Modify: `AWSSSMParamStoreUI/Views/Graph/GraphScene.swift`

- [ ] **Step 1: Add search ring to GraphNodeSprite**

Add to `GraphNodeSprite`:

```swift
private lazy var searchRing: SKShapeNode = {
    let r = SKShapeNode(circleOfRadius: Self.radius(for: kind) + 3)
    r.strokeColor = NSColor.systemTeal
    r.lineWidth = 2
    r.fillColor = .clear
    r.glowWidth = 2
    r.isHidden = true
    addChild(r)
    return r
}()

func setSearchHighlighted(_ highlighted: Bool) {
    searchRing.isHidden = !highlighted
}
```

- [ ] **Step 2: Add `applySearchHighlights` to GraphScene**

```swift
func applySearchHighlights() {
    guard let vm = viewModel else { return }
    let matches = vm.matchingNodeIds
    let hasSearch = !matches.isEmpty
    for (id, sprite) in nodeSprites {
        if hasSearch {
            let isMatch = matches.contains(id)
            sprite.setSearchHighlighted(isMatch)
            sprite.setDimmed(!isMatch)
        } else {
            sprite.setSearchHighlighted(false)
            // Dimming via selection still applies if there is a selection
            let selected = vm.selectedNodeId
            sprite.setDimmed(selected != nil && selected != id)
        }
    }
}

func fitToMatches(animated: Bool) {
    guard let vm = viewModel else { return }
    let matches = vm.matchingNodeIds
    guard !matches.isEmpty else { return }
    var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
    var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
    for id in matches {
        guard let s = nodeSprites[id] else { continue }
        minX = min(minX, s.position.x); minY = min(minY, s.position.y)
        maxX = max(maxX, s.position.x); maxY = max(maxY, s.position.y)
    }
    let pad: CGFloat = 60
    let w = (maxX - minX) + 2 * pad
    let h = (maxY - minY) + 2 * pad
    let viewSize = view?.bounds.size ?? size
    let scale = max(w / viewSize.width, h / viewSize.height, 0.1)
    let center = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
    cameraNode.run(SKAction.group([
        SKAction.move(to: center, duration: animated ? 0.3 : 0),
        SKAction.scale(to: max(0.1, min(4.0, scale)), duration: animated ? 0.3 : 0)
    ]))
}
```

- [ ] **Step 3: Build**

Expected: `Build succeeded`.

- [ ] **Step 4: Commit**

```
git add AWSSSMParamStoreUI/Views/Graph/GraphNodeSprite.swift \
        AWSSSMParamStoreUI/Views/Graph/GraphScene.swift
git commit -m "Add search highlighting to graph"
```

---

## Task 16: GraphInfoCard view

SwiftUI bottom-center card showing the selected node's path, value, type, version, "updated X ago", and an "Open ↗" button.

**Files:**
- Create: `AWSSSMParamStoreUI/Views/Graph/GraphInfoCard.swift`

- [ ] **Step 1: Implement view**

Create `AWSSSMParamStoreUI/Views/Graph/GraphInfoCard.swift`:

```swift
import SwiftUI

struct GraphInfoCard: View {
    let node: ConfigNode
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(node.fullPath)
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let value = displayValue {
                    Text(value)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                HStack(spacing: 10) {
                    if let type = node.type { Text(type) }
                    if let v = node.version { Text("v\(v)") }
                    if let modified = node.lastModified {
                        Text("updated \(modified.formatted(.relative(presentation: .named)))")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onOpen) {
                Label("Open", systemImage: "arrow.up.right")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: 600)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(radius: 6, y: 2)
    }

    private var displayValue: String? {
        if node.type == "SecureString" {
            return "••••••••"
        }
        return node.value ?? node.serverValue
    }
}
```

- [ ] **Step 2: Build**

Expected: `Build succeeded`.

- [ ] **Step 3: Commit**

```
git add AWSSSMParamStoreUI/Views/Graph/GraphInfoCard.swift \
        AWSSSMParamStoreUI.xcodeproj/project.pbxproj
git commit -m "Add GraphInfoCard view"
```

---

## Task 17: MiniMapView

SwiftUI overview rendering all nodes as 2px dots and a viewport rectangle reflecting the camera. Reads positions on every render.

**Files:**
- Create: `AWSSSMParamStoreUI/Views/Graph/MiniMapView.swift`

- [ ] **Step 1: Implement MiniMapView**

Create `AWSSSMParamStoreUI/Views/Graph/MiniMapView.swift`:

```swift
import SwiftUI

struct MiniMapView: View {
    /// Snapshot of node positions and viewport rect for this paint cycle.
    let nodePositions: [CGPoint]
    let viewportRect: CGRect   // in scene coordinates
    let allBounds: CGRect      // bounding rect of all nodes in scene coordinates

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.7)
                ForEach(0..<nodePositions.count, id: \.self) { i in
                    let p = nodePositions[i]
                    let mapped = map(point: p, in: geo.size)
                    Circle()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 2, height: 2)
                        .position(mapped)
                }
                let vpRect = mapRect(viewportRect, in: geo.size)
                Rectangle()
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    .background(Color.accentColor.opacity(0.08))
                    .frame(width: vpRect.width, height: vpRect.height)
                    .position(x: vpRect.midX, y: vpRect.midY)
            }
        }
        .frame(width: 150, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func map(point p: CGPoint, in size: CGSize) -> CGPoint {
        let bw = max(allBounds.width, 1)
        let bh = max(allBounds.height, 1)
        let nx = (p.x - allBounds.minX) / bw
        let ny = (p.y - allBounds.minY) / bh
        // Flip Y: SpriteKit Y-up → SwiftUI Y-down
        return CGPoint(x: nx * size.width, y: (1 - ny) * size.height)
    }

    private func mapRect(_ r: CGRect, in size: CGSize) -> CGRect {
        let topLeft = map(point: CGPoint(x: r.minX, y: r.maxY), in: size)
        let bottomRight = map(point: CGPoint(x: r.maxX, y: r.minY), in: size)
        return CGRect(x: topLeft.x, y: topLeft.y,
                      width: bottomRight.x - topLeft.x,
                      height: bottomRight.y - topLeft.y)
    }
}
```

- [ ] **Step 2: Build**

Expected: `Build succeeded`.

- [ ] **Step 3: Commit**

```
git add AWSSSMParamStoreUI/Views/Graph/MiniMapView.swift \
        AWSSSMParamStoreUI.xcodeproj/project.pbxproj
git commit -m "Add MiniMapView for graph overview"
```

---

## Task 18: GraphSheet root view

Assembles SpriteView + toolbar + info card + mini-map in a `ZStack`. Wires search, fit, reset, SVG export, and close.

**Files:**
- Create: `AWSSSMParamStoreUI/Views/Graph/GraphSheet.swift`

- [ ] **Step 1: Implement GraphSheet**

Create `AWSSSMParamStoreUI/Views/Graph/GraphSheet.swift`:

```swift
import SwiftUI
import SpriteKit
import AppKit
import UniformTypeIdentifiers

struct GraphSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = GraphViewModel()

    // Holds the SKScene across renders.
    @State private var scene: GraphScene = {
        let s = GraphScene(size: CGSize(width: 1200, height: 800))
        s.scaleMode = .resizeFill
        return s
    }()

    @State private var miniMapNodePositions: [CGPoint] = []
    @State private var miniMapAllBounds: CGRect = .zero
    @State private var miniMapViewport: CGRect = .zero

    var body: some View {
        ZStack(alignment: .top) {
            if viewModel.snapshot.nodes.count <= 1 {
                emptyState
            } else {
                SpriteView(scene: scene, options: [.allowsTransparency])
                    .ignoresSafeArea()

                toolbar
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                if let selected = selectedConfigNode {
                    VStack { Spacer()
                        GraphInfoCard(node: selected) { openSelected() }
                            .padding(.bottom, 16)
                    }
                }

                VStack { Spacer()
                    HStack { Spacer()
                        MiniMapView(nodePositions: miniMapNodePositions,
                                    viewportRect: miniMapViewport,
                                    allBounds: miniMapAllBounds)
                            .padding(.trailing, 16)
                            .padding(.bottom, 16)
                    }
                }
            }
        }
        .frame(minWidth: 800, idealWidth: 1200, minHeight: 600, idealHeight: 800)
        .onAppear { configureScene() }
        .onChange(of: colorScheme) { _, newScheme in
            scene.theme = GraphTheme(colorScheme: newScheme)
        }
        .onChange(of: viewModel.searchText) { _, _ in
            scene.applySearchHighlights()
        }
        .onChange(of: viewModel.selectedNodeId) { _, _ in
            scene.refreshSelectionVisuals()
        }
        // Refresh mini-map periodically while open.
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            updateMiniMap()
        }
    }

    // MARK: Subviews

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
            }.help("Close (⌘W)")

            Divider().frame(height: 18)

            TextField("Search nodes…", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
                .onSubmit { scene.fitToMatches(animated: true) }

            Spacer()

            Button(action: { scene.fitToView(animated: true) }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help("Fit to view (⌘1)")
            .keyboardShortcut("1", modifiers: .command)

            Button(action: { scene.resetZoom(animated: true) }) {
                Image(systemName: "arrow.counterclockwise")
            }
            .help("Reset zoom (⌘0)")
            .keyboardShortcut("0", modifiers: .command)

            Button(action: exportSVG) {
                Image(systemName: "square.and.arrow.down")
            }.help("Export SVG")
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("No parameters in this connection")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("Close") { dismiss() }
                .padding(.top, 8)
        }
    }

    // MARK: Setup

    private func configureScene() {
        scene.theme = GraphTheme(colorScheme: colorScheme)
        let connectionName = appState.currentConnection?.name ?? "Connection"
        viewModel.load(rootNodes: appState.rootNodes, connectionName: connectionName)
        scene.populate(viewModel: viewModel)
        scene.onNavigateToLeaf = { nodeId in
            appState.selectedNodeId = nodeId
            dismiss()
        }
        scene.onRevealInExplorer = { nodeId in
            appState.selectedNodeId = nodeId
            dismiss()
        }
    }

    private var selectedConfigNode: ConfigNode? {
        guard let id = viewModel.selectedNodeId,
              id != GraphSnapshot.homeId else { return nil }
        return findConfigNode(id: id, in: appState.rootNodes)
    }

    private func findConfigNode(id: String, in nodes: [ConfigNode]) -> ConfigNode? {
        for node in nodes {
            if node.id == id { return node }
            if let found = findConfigNode(id: id, in: node.children ?? []) { return found }
        }
        return nil
    }

    private func openSelected() {
        guard let id = viewModel.selectedNodeId else { return }
        appState.selectedNodeId = id
        dismiss()
    }

    private func exportSVG() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "svg")!]
        let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let connName = appState.currentConnection?.name ?? "graph"
        panel.nameFieldStringValue = "\(connName)-\(stamp).svg"
        if panel.runModal() == .OK, let url = panel.url {
            let svg = scene.exportCurrentSceneAsSVG()
            try? svg.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func updateMiniMap() {
        let snapshot = scene.miniMapSnapshot()
        miniMapNodePositions = snapshot.nodePositions
        miniMapAllBounds = snapshot.allBounds
        miniMapViewport = snapshot.viewport
    }
}
```

- [ ] **Step 2: Add helper methods to GraphScene that GraphSheet calls**

Add to `GraphScene.swift`:

```swift
struct MiniMapSnapshot {
    let nodePositions: [CGPoint]
    let allBounds: CGRect
    let viewport: CGRect
}

func miniMapSnapshot() -> MiniMapSnapshot {
    var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
    var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
    var positions: [CGPoint] = []
    positions.reserveCapacity(nodeSprites.count)
    for sprite in nodeSprites.values {
        positions.append(sprite.position)
        minX = min(minX, sprite.position.x); minY = min(minY, sprite.position.y)
        maxX = max(maxX, sprite.position.x); maxY = max(maxY, sprite.position.y)
    }
    let bounds = (positions.isEmpty)
        ? CGRect(x: -100, y: -100, width: 200, height: 200)
        : CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    let viewSize = view?.bounds.size ?? size
    let halfW = viewSize.width * cameraNode.xScale * 0.5
    let halfH = viewSize.height * cameraNode.yScale * 0.5
    let vp = CGRect(x: cameraNode.position.x - halfW,
                    y: cameraNode.position.y - halfH,
                    width: halfW * 2,
                    height: halfH * 2)
    return MiniMapSnapshot(nodePositions: positions, allBounds: bounds, viewport: vp)
}

func exportCurrentSceneAsSVG() -> String {
    let posNodes: [GraphSVGExporter.PositionedNode] = nodeSprites.values.map { sprite in
        let snapshotNode = viewModel?.snapshot.nodes.first(where: { $0.id == sprite.snapshotNodeId })
        let color = snapshotNode.map { GraphNodeSprite.color(for: $0, theme: theme) } ?? .gray
        return GraphSVGExporter.PositionedNode(
            id: sprite.snapshotNodeId,
            x: Double(sprite.position.x),
            y: Double(-sprite.position.y), // flip Y for SVG (Y-down)
            radius: Double(GraphNodeSprite.radius(for: sprite.kind)),
            fillHex: color.toHex(),
            label: snapshotNode?.label ?? ""
        )
    }
    let posEdges: [GraphSVGExporter.PositionedEdge] = edgeSprites.compactMap { edge in
        guard let from = edge.fromNode, let to = edge.toNode else { return nil }
        return GraphSVGExporter.PositionedEdge(
            x1: Double(from.position.x), y1: Double(-from.position.y),
            x2: Double(to.position.x), y2: Double(-to.position.y)
        )
    }
    return GraphSVGExporter.export(
        nodes: posNodes, edges: posEdges,
        edgeColorHex: theme.edgeColor.toHex(),
        backgroundHex: theme.canvasBackground.toHex()
    )
}
```

Add NSColor → hex helper at the bottom of `GraphScene.swift`:

```swift
private extension NSColor {
    func toHex() -> String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}
```

- [ ] **Step 3: Add files to Xcode target, build**

Expected: `Build succeeded`.

- [ ] **Step 4: Commit**

```
git add AWSSSMParamStoreUI/Views/Graph/GraphSheet.swift \
        AWSSSMParamStoreUI/Views/Graph/GraphScene.swift \
        AWSSSMParamStoreUI.xcodeproj/project.pbxproj
git commit -m "Assemble GraphSheet with toolbar, info card, mini-map"
```

---

## Task 19: Wire ContentView toolbar button

Add a "Graph" button to `ContentView` toolbar in the trailing area; disabled when no active connection. Wire `.sheet(isPresented:)`.

**Files:**
- Modify: `AWSSSMParamStoreUI/ContentView.swift`

- [ ] **Step 1: Locate the existing trailing toolbar group**

Open `ContentView.swift`. Find the existing inspector toggle in `ToolbarItem(placement: .automatic)` near line 397:

```swift
ToolbarItem(placement: .automatic) {
    Button {
        appState.isInspectorPresented.toggle()
    } label: {
        Image(systemName: "sidebar.right")
    }
    .help("Toggle Inspector (⌥⌘I)")
}
```

- [ ] **Step 2: Add a `@State` for the sheet at the top of `ContentView`**

Find existing `@State` declarations in `ContentView` (search for `@State private var showingSettings`). Add:

```swift
@State private var showingGraph = false
```

- [ ] **Step 3: Add a Graph button just before the inspector toggle**

Insert this `ToolbarItem` before the existing `ToolbarItem(placement: .automatic)`:

```swift
ToolbarItem(placement: .automatic) {
    Button {
        showingGraph = true
    } label: {
        Image(systemName: "circle.hexagongrid")
    }
    .disabled(appState.currentConnection == nil || !appState.isConnected)
    .help("Show Graph (⌘G)")
}
```

- [ ] **Step 4: Add the sheet modifier**

Find the existing `.sheet(isPresented: $showingSettings)` modifier. Add immediately after it (chained):

```swift
.sheet(isPresented: $showingGraph) {
    GraphSheet()
        .environmentObject(appState)
}
```

- [ ] **Step 5: Build, verify the toolbar button appears and is disabled when no connection**

```
xcodebuild -scheme AWSSSMParamStoreUI -destination 'platform=macOS' build 2>&1 \
  | grep -E "(error:|Build succeeded|Build FAILED)"
```
Expected: `Build succeeded`.

Manual: launch the app. Without a connection, the Graph button is disabled. Connect to LocalStack or AWS — the button enables. Click it; sheet opens; if there are 0 params, the empty state shows.

- [ ] **Step 6: Commit**

```
git add AWSSSMParamStoreUI/ContentView.swift
git commit -m "Add Graph toolbar button to ContentView"
```

---

## Task 20: Add ⌘G menu command

Add `View → Show Graph` to the app menu, bound to ⌘G, enabled only when a connection is active.

**Files:**
- Modify: `AWSSSMParamStoreUI/AWSSSMParamStoreUIApp.swift`
- Modify: `AWSSSMParamStoreUI/Models/AppState.swift`

- [ ] **Step 1: Add a `showGraphRequested` published trigger to AppState**

In `AppState.swift`, add near the other `@Published` properties:

```swift
/// Set to true to request the main window to open the Graph sheet.
/// ContentView observes this and sets it back to false after handling.
@Published var showGraphRequested: Bool = false
```

- [ ] **Step 2: Have ContentView open the sheet when AppState requests it**

In `ContentView.swift`, add an `.onChange` after the `showingGraph` sheet modifier:

```swift
.onChange(of: appState.showGraphRequested) { _, requested in
    if requested {
        showingGraph = true
        appState.showGraphRequested = false
    }
}
```

- [ ] **Step 3: Add the menu command**

In `AWSSSMParamStoreUIApp.swift`, inside `.commands { ... }`, add a new `CommandMenu` (or `CommandGroup` after `.windowArrangement`):

```swift
CommandGroup(after: .windowArrangement) {
    Button("Show Graph") {
        appState?.showGraphRequested = true
    }
    .keyboardShortcut("g", modifiers: [.command])
    .disabled(appState?.currentConnection == nil || appState?.isConnected != true)
}
```

- [ ] **Step 4: Build and manually verify**

```
xcodebuild -scheme AWSSSMParamStoreUI -destination 'platform=macOS' build 2>&1 \
  | grep -E "(error:|Build succeeded|Build FAILED)"
```
Expected: `Build succeeded`.

Manual: launch app, connect, press ⌘G. Sheet should open.

- [ ] **Step 5: Commit**

```
git add AWSSSMParamStoreUI/AWSSSMParamStoreUIApp.swift \
        AWSSSMParamStoreUI/ContentView.swift \
        AWSSSMParamStoreUI/Models/AppState.swift
git commit -m "Add ⌘G menu command for Graph"
```

---

## Task 21: Settling pill

Show "Arranging…" overlay until the scene auto-freezes, then fade out.

**Files:**
- Modify: `AWSSSMParamStoreUI/Views/Graph/GraphScene.swift`
- Modify: `AWSSSMParamStoreUI/Views/Graph/GraphSheet.swift`

- [ ] **Step 1: Expose physics state from GraphScene**

Add to `GraphScene`:

```swift
/// Published-style flag readable from SwiftUI via `onSettleChange` callback.
var onSettleChange: ((Bool) -> Void)?

private var isSettled: Bool = false {
    didSet {
        if isSettled != oldValue { onSettleChange?(isSettled) }
    }
}
```

In `update(_:)`, replace the freeze line `physicsWorld.speed = 0` with:

```swift
physicsWorld.speed = 0
isSettled = true
```

At the end of `rebuild()`, after `physicsWorld.speed = 1`, add:

```swift
isSettled = false
```

- [ ] **Step 2: Show pill in GraphSheet**

In `GraphSheet`, add `@State private var isSettled = false` and overlay:

```swift
.onAppear {
    configureScene()
    scene.onSettleChange = { settled in
        DispatchQueue.main.async { self.isSettled = settled }
    }
}
```

Inside the `ZStack`, before the toolbar:

```swift
if !isSettled && viewModel.snapshot.nodes.count > 1 {
    VStack { Spacer()
        Text("Arranging…")
            .font(.caption)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 8)
        Spacer()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.leading, 16)
    .transition(.opacity)
}
```

- [ ] **Step 3: Build, manual verify**

Expected: `Build succeeded`. Open graph; the pill shows for 2-3 seconds, then fades.

- [ ] **Step 4: Commit**

```
git add AWSSSMParamStoreUI/Views/Graph/GraphScene.swift \
        AWSSSMParamStoreUI/Views/Graph/GraphSheet.swift
git commit -m "Add 'Arranging…' settling pill to GraphSheet"
```

---

## Task 22: Full theme reactivity (re-color sprites on scheme change)

Make the `theme` setter rebuild sprite colors without rebuilding positions.

**Files:**
- Modify: `AWSSSMParamStoreUI/Views/Graph/GraphScene.swift`

- [ ] **Step 1: Replace `applyTheme`**

Replace the existing `applyTheme()` body:

```swift
private func applyTheme() {
    backgroundColor = theme.canvasBackground
    for edge in edgeSprites { edge.strokeColor = theme.edgeColor }
    guard let vm = viewModel else { return }
    for (id, sprite) in nodeSprites {
        guard let snapshotNode = vm.snapshot.nodes.first(where: { $0.id == id }) else { continue }
        sprite.recolor(snapshotNode: snapshotNode, theme: theme)
    }
}
```

- [ ] **Step 2: Add `recolor` to GraphNodeSprite**

In `GraphNodeSprite`:

```swift
func recolor(snapshotNode: GraphSnapshot.Node, theme: GraphTheme) {
    circle.fillColor = Self.color(for: snapshotNode, theme: theme)
    labelNode.fontColor = theme.labelColor
    labelBackground.fillColor = theme.labelBackground
    selectionRing.strokeColor = theme.selectionRingColor
}
```

- [ ] **Step 3: Build, manual verify**

Expected: `Build succeeded`. Open graph in dark mode, switch System Settings → Appearance → Light. Colors update without rebuild.

- [ ] **Step 4: Commit**

```
git add AWSSSMParamStoreUI/Views/Graph/GraphScene.swift \
        AWSSSMParamStoreUI/Views/Graph/GraphNodeSprite.swift
git commit -m "Live re-color graph sprites on color scheme change"
```

---

## Task 23: Hover tracking via NSTrackingArea

`SpriteView` doesn't forward mouse-moved events by default. Wrap it in a representable that installs a tracking area.

**Files:**
- Create: `AWSSSMParamStoreUI/Views/Graph/HoverTrackingView.swift`
- Modify: `AWSSSMParamStoreUI/Views/Graph/GraphSheet.swift`

- [ ] **Step 1: Implement HoverTrackingView**

Create `AWSSSMParamStoreUI/Views/Graph/HoverTrackingView.swift`:

```swift
import SwiftUI
import AppKit
import SpriteKit

/// SwiftUI wrapper around SKView that adds NSTrackingArea for mouse-moved events.
/// Forwards the move (in scene coordinates) to the GraphScene's `handleMouseMoved`.
struct HoverTrackingSpriteView: NSViewRepresentable {
    let scene: GraphScene

    func makeNSView(context: Context) -> SKView {
        let view = SKView(frame: .zero)
        view.presentScene(scene)
        view.allowsTransparency = true
        view.ignoresSiblingOrder = true
        let area = NSTrackingArea(rect: .zero,
                                  options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
                                  owner: context.coordinator,
                                  userInfo: nil)
        view.addTrackingArea(area)
        context.coordinator.trackedView = view
        context.coordinator.scene = scene
        return view
    }

    func updateNSView(_ nsView: SKView, context: Context) {
        // SKView holds the scene; nothing to update.
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSResponder {
        weak var trackedView: SKView?
        weak var scene: GraphScene?

        override func mouseMoved(with event: NSEvent) {
            guard let view = trackedView, let scene = scene else { return }
            let pointInView = view.convert(event.locationInWindow, from: nil)
            let pointInScene = scene.convertPoint(fromView: pointInView)
            scene.handleMouseMoved(toScenePoint: pointInScene)
        }
    }
}
```

- [ ] **Step 2: Replace `SpriteView` in `GraphSheet` with the new wrapper**

In `GraphSheet`, change:

```swift
SpriteView(scene: scene, options: [.allowsTransparency])
    .ignoresSafeArea()
```

to:

```swift
HoverTrackingSpriteView(scene: scene)
    .ignoresSafeArea()
```

- [ ] **Step 3: Build, verify hover tooltips work**

Expected: `Build succeeded`. Open graph, move mouse over a node — its label appears.

- [ ] **Step 4: Commit**

```
git add AWSSSMParamStoreUI/Views/Graph/HoverTrackingView.swift \
        AWSSSMParamStoreUI/Views/Graph/GraphSheet.swift \
        AWSSSMParamStoreUI.xcodeproj/project.pbxproj
git commit -m "Add NSTrackingArea wrapper for hover labels"
```

---

## Task 24: Final manual verification & polish pass

Ship readiness check across the user flows in the spec.

- [ ] **Step 1: Run full build with all warnings**

```
xcodebuild -scheme AWSSSMParamStoreUI -destination 'platform=macOS' build 2>&1 \
  | grep -E "(error:|warning:|Build succeeded|Build FAILED)"
```
Expected: `Build succeeded`, no new warnings.

- [ ] **Step 2: Run full test suite**

```
xcodebuild test -scheme AWSSSMParamStoreUI -destination 'platform=macOS' 2>&1 \
  | grep -E "Test Suite|passed|failed"
```
Expected: all suites pass (`GraphThemeTests`, `GraphSnapshotTests`, `GraphViewModelTests`, `GraphSVGExporterTests`).

- [ ] **Step 3: Manual test against a small connection (~10 params)**

  - [ ] Toolbar button enabled, ⌘G works
  - [ ] Graph opens with home node + leaves radiating; settles in <2s
  - [ ] Pan with drag works; scroll wheel zooms with cursor as focal
  - [ ] ⌘1 fits all nodes; ⌘0 resets to home at 1×
  - [ ] Hover shows label
  - [ ] Single-click selects, info card appears, others dim
  - [ ] Click empty canvas deselects
  - [ ] Double-click leaf closes sheet, leaf is selected in sidebar
  - [ ] Double-click folder collapses; badge `+N` appears; double-click again expands
  - [ ] Right-click folder shows Expand/Collapse + View in Explorer
  - [ ] Right-click leaf shows View in Explorer
  - [ ] Right-click empty canvas: no menu
  - [ ] Search highlights matches, dims others; ↵ fits to matches
  - [ ] Mini-map shows dots and viewport rect
  - [ ] Toggle dark/light: colors update live
  - [ ] Export SVG saves a file that opens in browser

- [ ] **Step 4: Manual test against a large connection (~500-1500 params)**

  - [ ] Settles in ≤3s on M-series Mac
  - [ ] Pan/zoom remains smooth (60fps)
  - [ ] Hover/click responsive
  - [ ] No noticeable jank during search filter

- [ ] **Step 5: Commit any polish fixes**

If any issues surface, fix and commit individually (small focused commits per fix).

```
git status   # confirm clean tree
```

- [ ] **Step 6: Final summary commit (only if any spec note was updated)**

If iteration revealed spec gaps, update the spec doc then:

```
git add docs/superpowers/specs/2026-05-11-graph-feature-design.md
git commit -m "Update graph spec with notes from implementation"
```

---

## Self-Review

| Spec section | Covered by task |
|--------------|------------------|
| §3.1 Opening the graph | Tasks 18, 19, 20 |
| §3.2 Exploring (pan/zoom, fit, reset) | Tasks 11, 18 |
| §3.3 Selecting a node + info card | Tasks 12, 16, 18 |
| §3.4 Navigating to a node | Tasks 13, 14, 18, 19, 20 |
| §3.5 Collapse/expand | Tasks 3, 13, 14 |
| §3.6 Search | Tasks 4, 15, 18 |
| §3.7 SVG export | Tasks 5, 18 |
| §4.1 New files | All tasks |
| §4.2 Touched files (ContentView, App) | Tasks 19, 20 |
| §4.3 Snapshot model | Tasks 2, 18 |
| §5 Physics | Tasks 6, 9, 10 |
| §6 Toolbar | Task 18 |
| §7 Empty / settling pill / theme | Tasks 18, 21, 22 |
| §8 Accessibility (toolbar a11y, ⌘F focus) | Tasks 18, 24 |
| §9 Testing strategy | Tasks 1-5 unit tests; Task 24 manual |
