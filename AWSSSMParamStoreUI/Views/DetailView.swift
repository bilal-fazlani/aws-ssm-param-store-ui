import SwiftUI

struct DetailView: View {
    let node: ConfigNode
    @Binding var selection: String?
    @Binding var focusRequest: Bool
    var onNavigateToSidebar: () -> Void = {}
    @EnvironmentObject var appState: AppState
    @State private var editedValue: String = ""
    @State private var isSaving: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @FocusState private var isEditorFocused: Bool
    
    private var hasChanges: Bool {
        editedValue != node.serverValue
    }
    
    // Get parent path from current node's path
    private var parentPath: String? {
        let components = node.fullPath.split(separator: "/").dropLast()
        if components.isEmpty {
            return nil // At root level, go to home
        }
        return "/" + components.joined(separator: "/")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Breadcrumb navigation
            BreadcrumbView(path: node.fullPath, selection: $selection)
            
            // Text editor — or loading state while Phase 2 value fetch is in flight
            if node.isValueLoaded {
                TextEditor(text: $editedValue)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(hasChanges ? Color.orange.opacity(0.5) : Color.primary.opacity(0.1), lineWidth: 1)
                    )
                    .padding()
                    .focused($isEditorFocused)
                    .onKeyPress(.leftArrow) {
                        // At cursor position 0 with no selection → return focus to sidebar
                        guard let tv = NSApp.keyWindow?.firstResponder as? NSTextView,
                              tv.selectedRange.location == 0,
                              tv.selectedRange.length == 0 else { return .ignored }
                        onNavigateToSidebar()
                        return .handled
                    }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading value…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // Bottom bar - always visible
            HStack {
                // Delete button (red) — disabled until value is loaded
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .disabled(!node.isValueLoaded)
                .help("Delete this parameter")
                
                // Revert button
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        editedValue = node.serverValue ?? ""
                    }
                } label: {
                    Label("Revert", systemImage: "arrow.counterclockwise")
                }
                .disabled(!hasChanges)
                
                Spacer()
                
                // Last modified info
                if let lastMod = node.lastModified {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Updated \(lastMod, style: .relative)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Modified indicator
                if hasChanges {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 8, height: 8)
                        Text("Modified")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }
                
                Spacer()
                
                // Save button
                Button {
                    Task {
                        isSaving = true
                        await appState.save(nodeId: node.id, newValue: editedValue)
                        isSaving = false
                    }
                } label: {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Save", systemImage: "checkmark.circle.fill")
                    }
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(!hasChanges || isSaving || !node.isValueLoaded)
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .onAppear {
            editedValue = node.value ?? ""
            // focusRequest may already be true if selection + focus were set in the same
            // state batch — onChange won't fire on a newly-created view, so check here too
            if focusRequest {
                focusRequest = false
                DispatchQueue.main.async { isEditorFocused = true }
            }
        }
        .onChange(of: focusRequest) { _, requested in
            guard requested else { return }
            focusRequest = false
            DispatchQueue.main.async {
                isEditorFocused = true
                // Position cursor at start of value after brief delay to ensure TextView is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
                        textView.selectedRange = NSRange(location: 0, length: 0)
                    }
                }
            }
        }
        .onChange(of: node.serverValue) { _, newServerValue in
            if !node.isDirty, let val = newServerValue {
                withAnimation(.easeInOut(duration: 0.2)) {
                    editedValue = val
                }
            }
        }
        .onChange(of: editedValue) { _, newValue in
            appState.updateLocalValue(id: node.id, value: newValue)
        }
        .alert("Delete Parameter", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    selection = nil
                    await appState.deleteParameter(path: node.fullPath)
                }
            }
        } message: {
            Text("Are you sure you want to delete \"\(node.name)\"? This action cannot be undone.")
        }
        .background {
            // ESC: revert changes, go back to parent, focus sidebar
            Button("") {
                if hasChanges {
                    editedValue = node.serverValue ?? ""
                    appState.updateLocalValue(id: node.id, value: editedValue)
                }
                selection = parentPath
                onNavigateToSidebar()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .opacity(0)
        }
    }
}

// MARK: - Mesh Gradient Background

struct MeshGradientBackground: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.5, 0.5], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1]
            ],
            colors: colorScheme == .dark ? darkColors : lightColors
        )
    }
    
    private var darkColors: [Color] {
        [
            Color.blue.opacity(0.08), Color.purple.opacity(0.04), Color.blue.opacity(0.06),
            Color.cyan.opacity(0.04), Color.clear, Color.purple.opacity(0.04),
            Color.blue.opacity(0.06), Color.cyan.opacity(0.04), Color.blue.opacity(0.08)
        ]
    }
    
    private var lightColors: [Color] {
        [
            Color.blue.opacity(0.05), Color.purple.opacity(0.02), Color.blue.opacity(0.04),
            Color.cyan.opacity(0.02), Color.clear, Color.purple.opacity(0.02),
            Color.blue.opacity(0.04), Color.cyan.opacity(0.02), Color.blue.opacity(0.05)
        ]
    }
}




// MARK: - Folder Summary View

struct FolderSummaryView: View {
    let node: ConfigNode
    @Binding var selection: String?
    @EnvironmentObject var appState: AppState
    
    private var children: [ConfigNode] {
        node.children ?? []
    }
    
    private var parameterCount: Int {
        children.filter { $0.isLeaf }.count
    }
    
    private var folderCount: Int {
        children.filter { !$0.isLeaf }.count
    }
    
    private var totalDescendants: Int {
        node.totalLeafCount
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Breadcrumb navigation
            BreadcrumbView(path: node.fullPath, selection: $selection)
            
            // Content
            VStack(alignment: .leading, spacing: 16) {
                // Colored Statistics Grid (like Reminders app)
                HStack(spacing: 12) {
                    StatBox(
                        icon: "doc.text.fill",
                        color: .gray,
                        count: parameterCount,
                        label: "Parameters"
                    )
                    
                    StatBox(
                        icon: "folder.fill",
                        color: .blue,
                        count: folderCount,
                        label: "Folders"
                    )
                    
                    StatBox(
                        icon: "square.stack.3d.up.fill",
                        color: .gray,
                        count: totalDescendants,
                        label: "Total Parameters"
                    )
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                // Children List Card with material background
                ChildrenListCard(
                    children: children,
                    selection: $selection
                )
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
    }
}

// MARK: - Stat Box (Reminders-style colored box)

struct StatBox: View {
    let icon: String
    let color: Color
    let count: Int
    let label: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(count)")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
            }
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(color.gradient, in: RoundedRectangle(cornerRadius: 12))
    }
}


// MARK: - Children List Card

struct ChildrenListCard: View {
    let children: [ConfigNode]
    @Binding var selection: String?
    @EnvironmentObject var appState: AppState
    @State private var nodeToDelete: ConfigNode?
    @State private var showDeleteConfirmation = false
    
    private var folders: [ConfigNode] {
        children.filter { !$0.isLeaf }.sorted { $0.name < $1.name }
    }
    
    private var parameters: [ConfigNode] {
        children.filter { $0.isLeaf }.sorted { $0.name < $1.name }
    }
    
    private var deleteMessage: String {
        guard let node = nodeToDelete else { return "" }
        if node.isLeaf {
            return "Are you sure you want to delete \"\(node.name)\"? This action cannot be undone."
        } else {
            let count = node.totalDescendantCount
            return "Are you sure you want to delete \"\(node.name)\" and all \(count) items inside? This action cannot be undone."
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Contents")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("\(children.count) items")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            
            Divider()
            
            // Children list with sections
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                    // Folders section
                    if !folders.isEmpty {
                        Section {
                            ForEach(folders) { child in
                                ChildRow(node: child, onDelete: {
                                    nodeToDelete = child
                                    showDeleteConfirmation = true
                                })
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selection = child.id
                                    }
                            }
                        } header: {
                            SectionHeader(title: "Folders", count: folders.count)
                        }
                    }
                    
                    // Parameters section
                    if !parameters.isEmpty {
                        Section {
                            ForEach(parameters) { child in
                                ChildRow(node: child, onDelete: {
                                    nodeToDelete = child
                                    showDeleteConfirmation = true
                                })
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selection = child.id
                                    }
                            }
                        } header: {
                            SectionHeader(title: "Parameters", count: parameters.count)
                        }
                    }
                }
                .padding(.bottom)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .alert(nodeToDelete?.isLeaf == true ? "Delete Parameter" : "Delete Folder", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                nodeToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let node = nodeToDelete {
                    Task {
                        if node.isLeaf {
                            await appState.deleteParameter(path: node.fullPath)
                        } else {
                            await appState.deleteFolder(node)
                        }
                        nodeToDelete = nil
                    }
                }
            }
        } message: {
            Text(deleteMessage)
        }
    }
}

struct SectionHeader: View {
    let title: String
    let count: Int
    
    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Breadcrumb View

struct BreadcrumbView: View {
    let path: String  // e.g., "/config/fraud-service/my-flag"
    @Binding var selection: String?
    
    private var segments: [(name: String, path: String)] {
        var result: [(name: String, path: String)] = []
        let components = path.split(separator: "/").map(String.init)
        var currentPath = ""
        
        for component in components {
            currentPath += "/\(component)"
            result.append((name: component, path: currentPath))
        }
        
        return result
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                // Root/Home button
                Button {
                    selection = nil
                } label: {
                    Image(systemName: "house.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                
                // Path segments
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    // Chevron separator
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    
                    // Segment button
                    if index == segments.count - 1 {
                        // Current segment (not clickable, highlighted)
                        Text(segment.name)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                    } else {
                        // Parent segment (clickable)
                        Button {
                            selection = segment.path
                        } label: {
                            Text(segment.name)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }
}

struct ChildRow: View {
    let node: ConfigNode
    let onDelete: () -> Void
    @State private var isHovered = false
    
    private func abbreviateType(_ type: String) -> String {
        switch type {
        case "SecureString": return "Sec"
        case "StringList": return "List"
        case "String": return "Str"
        default: return type
        }
    }
    
    private var valuePreview: String? {
        guard node.isLeaf, let value = node.value, !value.isEmpty else { return nil }
        // Don't show preview for secure strings
        if node.type == "SecureString" { return "••••••••" }
        let firstLine = value.components(separatedBy: .newlines).first ?? value
        if firstLine.count > 60 {
            return String(firstLine.prefix(60)) + "..."
        }
        return firstLine
    }
    
    // Functional color logic:
    // - Folders = blue
    // - SecureString = red
    // - Normal = gray
    private var iconColor: Color {
        if !node.isLeaf {
            return .blue
        }
        if node.type == "SecureString" {
            return .red
        }
        return .gray
    }
    
    private var isSecure: Bool {
        node.type == "SecureString"
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Colored icon with background
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.gradient)
                    .frame(width: 32, height: 32)
                Image(systemName: node.isLeaf ? (isSecure ? "lock.fill" : "doc.text.fill") : "folder.fill")
                    .foregroundStyle(.white)
                    .font(.system(size: 14, weight: .medium))
            }
            
            // Name and value preview
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(node.name)
                        .font(.body.weight(.medium))
                    
                    // Dirty indicator (orange dot)
                    if node.isDirty {
                        Circle()
                            .fill(.orange)
                            .frame(width: 8, height: 8)
                    }
                }
                
                // Value preview for leaf nodes
                if let preview = valuePreview {
                    Text(preview)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Time + Type for leaf nodes, Count for folders
            if node.isLeaf {
                VStack(alignment: .trailing, spacing: 2) {
                    if let lastMod = node.lastModified {
                        Text(lastMod, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let type = node.type {
                        Text(abbreviateType(type))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("\(node.children?.count ?? 0)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            if node.isLeaf {
                Button("Copy Value", systemImage: "doc.on.doc") {
                    if let value = node.value {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(value, forType: .string)
                    }
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
}
