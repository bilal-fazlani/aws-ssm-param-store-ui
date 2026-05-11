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
