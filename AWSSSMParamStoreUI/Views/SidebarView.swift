import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selection: String?
    @Binding var focusRequest: Bool
    var onEnterDetail: () -> Void = {}
    @State private var expandedFolders: Set<String> = []
    @FocusState private var isListFocused: Bool

    var body: some View {
        Group {
            // Main List with shimmer loading or content
            if appState.isLoading && appState.rootNodes.isEmpty {
                // Shimmer skeleton while loading
                List {
                    ForEach(0..<8, id: \.self) { i in
                        ShimmerListItem(isFolder: i % 3 == 0)
                    }
                }
                .listStyle(.sidebar)
            } else {
                ScrollViewReader { proxy in
                    List(selection: $selection) {
                        let rootFolders = appState.rootNodes.filter { !$0.isLeaf }
                        let rootLeaves  = appState.rootNodes.filter {  $0.isLeaf }
                        ForEach(rootFolders) { node in
                            NodeTreeView(node: node, selection: $selection, expandedFolders: $expandedFolders)
                        }
                        if !rootFolders.isEmpty && !rootLeaves.isEmpty {
                            Divider()
                        }
                        ForEach(rootLeaves) { node in
                            NodeTreeView(node: node, selection: $selection, expandedFolders: $expandedFolders)
                        }
                    }
                    .listStyle(.sidebar)
                    .animation(nil, value: appState.rootNodes)
                    .animation(nil, value: expandedFolders)
                    .focused($isListFocused)
                    .onKeyPress(.rightArrow) {
                        guard let id = selection,
                              let node = findNode(id: id, in: appState.rootNodes),
                              node.isLeaf else { return .ignored }
                        onEnterDetail()
                        return .handled
                    }
                    .onChange(of: focusRequest) { _, requested in
                        guard requested else { return }
                        focusRequest = false
                        DispatchQueue.main.async {
                            isListFocused = true
                            // Scroll to selected item if it exists
                            if let selectedId = selection {
                                proxy.scrollTo(selectedId)
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: selection) { _, newSelection in
            // Expand all parent folders when selection changes
            if let selectedId = newSelection {
                expandParents(for: selectedId)
            }
        }
        .onAppear {
            // Expand parents if there's an initial selection
            if let selectedId = selection {
                expandParents(for: selectedId)
            }
        }
    }
    
    // MARK: - Node Lookup

    private func findNode(id: String, in nodes: [ConfigNode]) -> ConfigNode? {
        for node in nodes {
            if node.id == id { return node }
            if let children = node.children, let found = findNode(id: id, in: children) {
                return found
            }
        }
        return nil
    }

    // MARK: - Expand Parents
    
    private func expandParents(for nodeId: String) {
        // Find all parent folder IDs for the given node
        if let parentIds = findParentIds(for: nodeId, in: appState.rootNodes, path: []) {
            for parentId in parentIds {
                expandedFolders.insert(parentId)
            }
        }
    }
    
    private func findParentIds(for targetId: String, in nodes: [ConfigNode], path: [String]) -> [String]? {
        for node in nodes {
            if node.id == targetId {
                // Found the target - return the accumulated path
                return path
            }
            if let children = node.children {
                // Recurse with current node added to path
                if let result = findParentIds(for: targetId, in: children, path: path + [node.id]) {
                    // Found in subtree - return the result as-is
                    return result
                }
            }
        }
        // Not found in this branch
        return nil
    }
}

// MARK: - Node Tree View (Recursive)

struct NodeTreeView: View {
    let node: ConfigNode
    @Binding var selection: String?
    @Binding var expandedFolders: Set<String>
    @EnvironmentObject var appState: AppState
    @State private var showDeleteConfirmation = false
    
    private var isExpanded: Binding<Bool> {
        Binding(
            get: { expandedFolders.contains(node.id) },
            set: { newValue in
                if newValue {
                    expandedFolders.insert(node.id)
                } else {
                    expandedFolders.remove(node.id)
                }
            }
        )
    }
    
    private var deleteMessage: String {
        if node.isLeaf {
            return "Are you sure you want to delete \"\(node.name)\"? This action cannot be undone."
        } else {
            let count = node.totalDescendantCount
            return "Are you sure you want to delete \"\(node.name)\" and all \(count) items inside? This action cannot be undone."
        }
    }
    
    var body: some View {
        Group {
            if node.isLeaf {
                ParameterRow(node: node, onDelete: { showDeleteConfirmation = true })
                    .tag(node.id)
            } else {
                DisclosureGroup(isExpanded: isExpanded) {
                    if let children = node.children {
                        ForEach(children) { child in
                            NodeTreeView(node: child, selection: $selection, expandedFolders: $expandedFolders)
                        }
                    }
                } label: {
                    FolderRow(node: node, onDelete: { showDeleteConfirmation = true })
                        .tag(node.id)
                }
            }
        }
        .alert(node.isLeaf ? "Delete Parameter" : "Delete Folder", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    if selection == node.id { selection = nil }
                    if node.isLeaf {
                        await appState.deleteParameter(path: node.fullPath)
                    } else {
                        await appState.deleteFolder(node)
                    }
                }
            }
        } message: {
            Text(deleteMessage)
        }
    }
    
}

// MARK: - Parameter Row

struct ParameterRow: View {
    let node: ConfigNode
    let onDelete: () -> Void
    
    // Functional color logic:
    // - SecureString = red (sensitive)
    // - Normal = gray
    private var iconColor: Color {
        if node.type == "SecureString" {
            return .red
        }
        return .gray
    }
    
    private var isSecure: Bool {
        node.type == "SecureString"
    }
    
    var body: some View {
        HStack(spacing: 10) {
            // Colored icon with background
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(iconColor.gradient)
                    .frame(width: 24, height: 24)
                Image(systemName: isSecure ? "lock.fill" : "doc.text.fill")
                    .foregroundStyle(.white)
                    .font(.system(size: 11, weight: .medium))
            }
            
            // Name
            Text(node.name)
                .foregroundStyle(node.isPending ? Color.secondary : (node.isDirty ? Color.orange : Color.primary))
                .fontWeight(node.isDirty ? .medium : .regular)

            Spacer()

            // Pending indicator (spinner while AWS add is in flight)
            if node.isPending {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.8)
            }

            // Dirty indicator (orange dot)
            if node.isDirty {
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
            }

            // Type badge — fixed width keeps dirty dot and spinner at a stable position
            if let type = node.type {
                Text(abbreviateType(type))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Copy Value", systemImage: "doc.on.doc") {
                if let value = node.value {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                }
            }
            Button("Copy Path", systemImage: "link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.fullPath, forType: .string)
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                onDelete()
            }
        }
    }
    
    private func abbreviateType(_ type: String) -> String {
        switch type {
        case "SecureString": return "Sec"
        case "StringList": return "List"
        case "String": return "Str"
        default: return type
        }
    }
}

// MARK: - Folder Row

struct FolderRow: View {
    let node: ConfigNode
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Blue folder icon for all folders
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.blue.gradient)
                    .frame(width: 24, height: 24)
                Image(systemName: "folder.fill")
                    .foregroundStyle(.white)
                    .font(.system(size: 12))
            }

            Text(node.name)
                .fontWeight(.medium)

            Spacer()

            Text("\(node.totalLeafCount)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color.secondary.opacity(0.1))
                )
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Copy Path", systemImage: "link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.fullPath, forType: .string)
            }
            Divider()
            Button("Delete Folder", systemImage: "trash", role: .destructive) {
                onDelete()
            }
        }
    }
}
