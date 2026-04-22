import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selection: String?
    @Binding var focusRequest: Bool
    var onEnterDetail: () -> Void = {}
    var onAdd: (String?) -> Void = { _ in }
    @State private var expandedFolders: Set<String> = []
    @FocusState private var isListFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
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
                                NodeTreeView(
                                    node: node,
                                    selection: $selection,
                                    expandedFolders: $expandedFolders,
                                    onAddUnderFolder: { path in onAdd(path) }
                                )
                            }
                            if !rootFolders.isEmpty && !rootLeaves.isEmpty {
                                Divider()
                            }
                            ForEach(rootLeaves) { node in
                                NodeTreeView(
                                    node: node,
                                    selection: $selection,
                                    expandedFolders: $expandedFolders,
                                    onAddUnderFolder: { path in onAdd(path) }
                                )
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
            .frame(maxHeight: .infinity)

            Divider()

            AddParameterFooterButton(
                disabledReason: footerDisabledReason,
                onTap: { onAdd(nil) }
            )
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
    
    // MARK: - Footer

    private var footerDisabledReason: String? {
        if appState.isConnecting { return "Connecting…" }
        if appState.currentConnection == nil { return "Connect to a source to add parameters" }
        return nil
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
    let onAddUnderFolder: (String) -> Void
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
            let count = node.totalLeafCount
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
                            NodeTreeView(
                                node: child,
                                selection: $selection,
                                expandedFolders: $expandedFolders,
                                onAddUnderFolder: onAddUnderFolder
                            )
                        }
                    }
                } label: {
                    FolderRow(
                        node: node,
                        isSelected: selection == node.id,
                        onAdd: { onAddUnderFolder(node.fullPath) },
                        onDelete: { showDeleteConfirmation = true }
                    )
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
    // - StringList = purple
    // - Normal = gray
    private var iconColor: Color {
        if node.type == "SecureString" {
            return .red
        }
        if node.type == "StringList" {
            return .purple
        }
        return .gray
    }
    
    private var iconName: String {
        if node.type == "SecureString" { return "lock.fill" }
        if node.type == "StringList" { return "list.bullet" }
        return "doc.text.fill"
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
                Image(systemName: iconName)
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
    let isSelected: Bool
    let onAdd: () -> Void
    let onDelete: () -> Void
    @State private var isHovered: Bool = false

    // White pops on the selected-row accent-blue background; accent pops on the
    // default dark row background. Either way the "+" stays readable.
    private var plusColor: Color {
        isSelected ? .white : .accentColor
    }

    private var shortType: String {
        switch node.type ?? "String" {
        case "SecureString": return "Sec"
        case "StringList": return "List"
        case "String": return "Str"
        default: return node.type ?? "Str"
        }
    }

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

            if node.isValueNode {
                Text(shortType)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.1)))
            }

            Spacer()

            if isHovered {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(plusColor)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(HoverTintButtonStyle(tint: plusColor))
                .help("Add parameter under \(node.fullPath)")
                .transition(.opacity)
            } else {
                Text("\(node.totalLeafCount)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.1))
                    )
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
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

// MARK: - Add Parameter Footer Button

private struct AddParameterFooterButton: View {
    let disabledReason: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("Add Parameter")
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .disabled(disabledReason != nil)
        .help(disabledReason ?? "Add Parameter (⇧⌘N)")
        .padding(10)
    }
}

// MARK: - Hover Tint Button Style

private struct HoverTintButtonStyle: ButtonStyle {
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        HoverTintBody(configuration: configuration, tint: tint)
    }

    private struct HoverTintBody: View {
        let configuration: ButtonStyle.Configuration
        let tint: Color
        @State private var isHot: Bool = false

        var body: some View {
            configuration.label
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHot ? tint.opacity(0.22) : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 5))
                .onHover { isHot = $0 }
                .opacity(configuration.isPressed ? 0.6 : 1)
        }
    }
}
