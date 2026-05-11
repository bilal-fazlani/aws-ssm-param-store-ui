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
