import Foundation
import Combine

@MainActor
final class GraphViewModel: ObservableObject {
    @Published private(set) var snapshot: GraphSnapshot = GraphSnapshot(nodes: [], edges: [])
    @Published private(set) var collapsedFolderIds: Set<String> = []
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

    /// IDs of nodes whose full path contains `searchText` (case-insensitive, trimmed).
    /// Empty when `searchText` is blank. Excludes the synthetic home node.
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
