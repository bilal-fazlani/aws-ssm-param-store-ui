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
