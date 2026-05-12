import SwiftUI
import SpriteKit
import AppKit
import Combine
import UniformTypeIdentifiers

struct GraphSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = GraphViewModel()

    @State private var scene: GraphScene = {
        let s = GraphScene(size: CGSize(width: 1200, height: 800))
        s.scaleMode = .resizeFill
        return s
    }()

    @State private var miniMapNodePositions: [CGPoint] = []
    @State private var miniMapAllBounds: CGRect = .zero
    @State private var miniMapViewport: CGRect = .zero
    @State private var isSettled = false

    var body: some View {
        ZStack(alignment: .top) {
            if viewModel.snapshot.nodes.count <= 1 {
                emptyState
            } else {
                HoverTrackingSpriteView(scene: scene)
                    .ignoresSafeArea()

                if !isSettled {
                    VStack {
                        Text("Arranging…")
                            .font(.caption)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.top, 60)
                            .padding(.leading, 16)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                }

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
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            updateMiniMap()
        }
    }

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
                .keyboardShortcut("f", modifiers: .command)

            Spacer()

            Text(nodeCountSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Total parameters / folders in this connection")

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
        scene.onSettleChange = { settled in
            DispatchQueue.main.async { withAnimation { isSettled = settled } }
        }
    }

    private var nodeCountSummary: String {
        var params = 0
        var folders = 0
        for node in viewModel.snapshot.nodes {
            switch node.kind {
            case .leaf: params += 1
            case .folder: folders += 1
            case .home: break
            }
        }
        return "\(params) params · \(folders) folders"
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
        if let svgType = UTType(filenameExtension: "svg") {
            panel.allowedContentTypes = [svgType]
        }
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
