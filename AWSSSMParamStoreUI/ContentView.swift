import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState()
    @ObservedObject private var connectionStore = ConnectionStore.shared
    @State private var selection: String?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showingAddSheet = false
    @State private var showingShortcuts = false
    @State private var showingSettings = false
    @State private var showingSearch = false
    @State private var sidebarFocusRequest = false
    @State private var detailFocusRequest = false
    @State private var lastConnectWasFromSheet = false
    
    private var parentId: String? {
        guard let selection = selection else { return nil }
        return findParentId(for: selection, in: appState.rootNodes)
    }
    
    // Get the path prefix for new values (always enabled)
    // If a value is selected, use its parent's path
    // If a folder is selected, use that folder's path
    // If nothing selected, use root
    private var newValuePathPrefix: String {
        guard let selection = selection,
              let node = findNode(id: selection, nodes: appState.rootNodes) else {
            return "/"
        }
        
        if node.isLeaf {
            // It's a value - get parent path
            if let parentId = parentId,
               let parentNode = findNode(id: parentId, nodes: appState.rootNodes) {
                return parentNode.fullPath + "/"
            }
            return "/" // Value at root level
        } else {
            // It's a folder
            return node.fullPath + "/"
        }
    }
    
    private var windowTitle: String {
        if let selection = selection,
           let node = findNode(id: selection, nodes: appState.rootNodes) {
            return node.fullPath
        }
        return "AWS SSM Param Store UI"
    }
    
    private var lastUpdatedText: String {
        if let progress = appState.valuesLoadProgress {
            return "Loading values \(progress.loaded)/\(progress.total)…"
        }
        if appState.isLoading {
            return "Syncing..."
        }
        if let lastUpdated = appState.lastUpdated {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Last updated: \(formatter.localizedString(for: lastUpdated, relativeTo: Date()))"
        }
        return ""
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                selection: $selection,
                focusRequest: $sidebarFocusRequest,
                onEnterDetail: { detailFocusRequest = true }
            )
            .environmentObject(appState)
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
        } detail: {
            if let selection = selection,
               let node = findNode(id: selection, nodes: appState.rootNodes) {
                if node.isLeaf {
                    DetailView(
                        node: node,
                        selection: $selection,
                        focusRequest: $detailFocusRequest,
                        onNavigateToSidebar: { sidebarFocusRequest = true }
                    )
                    .environmentObject(appState)
                    .id(node.id)
                } else {
                    FolderSummaryView(node: node, selection: $selection)
                        .environmentObject(appState)
                        .id(node.id)
                }
            } else {
                // Root level - show as folder view
                RootFolderView(selection: $selection)
                    .environmentObject(appState)
            }
        }
        .overlay {
            if appState.currentConnection == nil {
                ConnectionPickerOverlay(
                    connectionStore: connectionStore,
                    onConnect: { connection in
                        Task { await appState.connect(to: connection) }
                    },
                    onManage: { showingSettings = true }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.currentConnection == nil)
        .overlay {
            if showingSearch {
                SearchOverlayView(
                    isPresented: $showingSearch,
                    rootNodes: appState.rootNodes,
                    onSelect: { id in
                        selection = id
                        if let node = findNode(id: id, nodes: appState.rootNodes), node.isLeaf {
                            detailFocusRequest = true
                        } else {
                            sidebarFocusRequest = true
                        }
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showingSearch)
        .navigationTitle(windowTitle)
        .navigationSubtitle(lastUpdatedText)
        .toast(message: $appState.toastMessage, icon: "arrow.triangle.2.circlepath")
        .errorToast(message: $appState.errorMessage)
        .updateToast(version: $appState.availableUpdateVersion)
        .onAppear { appState.checkForUpdates() }
        .toolbar {
            // Navigation: Home & Back buttons grouped
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    selection = nil
                } label: {
                    Label("Home", systemImage: "house")
                        .labelStyle(.titleAndIcon)
                }
                .keyboardShortcut("h", modifiers: [.command])
                .disabled(selection == nil)
                .help("Go to home (⌘H)")
                
                Button {
                    selection = parentId
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(selection == nil)
                .help("Go to parent folder")
            }
            
           
            // Center & Right items with spacer-based layout
            ToolbarItem(placement: .principal) {
                // Add button (centered via spacers)
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .help("Add new parameter (⇧⌘N)")
                .disabled(appState.currentConnection == nil)
            }
            
            ToolbarItem(placement: .principal){
                // Info button (standalone)
                Button {
                    showingShortcuts = true
                } label: {
                    Label("Shortcuts", systemImage: "info.circle")
                        .labelStyle(.iconOnly)
                }
                .help("Keyboard Shortcuts")
                .popover(isPresented: $showingShortcuts, arrowEdge: .bottom) {
                    ShortcutsPopover()
                }
            }
            
            // Connection & Region grouped
            ToolbarItemGroup(placement: .automatic) {
                // Connection selector dropdown
                Menu {
                    if connectionStore.connections.isEmpty {
                        // No connections - show add option only
                        Button {
                            showingSettings = true
                        } label: {
                            Label("Add Connection...", systemImage: "plus")
                        }
                    } else {
                        // List saved connections
                        ForEach(connectionStore.connections) { connection in
                            Button {
                                Task {
                                    await appState.connect(to: connection)
                                    if appState.currentConnection?.id == connection.id {
                                        appState.showToast("Connected to \(connection.name)")
                                    }
                                }
                            } label: {
                                HStack {
                                    Label(connection.name, systemImage: connection.type.icon)
                                    Spacer()
                                    Text(connection.region)
                                        .foregroundStyle(.secondary)
                                    if appState.currentConnection?.id == connection.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        Button {
                            showingSettings = true
                        } label: {
                            Label("Manage Connections...", systemImage: "gear")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if appState.isConnecting {
                            ProgressView()
                                .controlSize(.small)
                            if let connection = appState.currentConnection {
                                Text(connection.name)
                                    .foregroundStyle(.secondary)
                            }
                        } else if let connection = appState.currentConnection {
                            Image(systemName: connection.type.icon)
                            Text(connection.name)
                            // Show error indicator if not connected
                            if !appState.isConnected {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                            }
                        } else {
                            Image(systemName: "externaldrive.badge.questionmark")
                            Text("No Connection")
                        }
                    }
                }
                .menuIndicator(.hidden)
                .disabled(appState.isConnecting)
                .help(appState.isConnecting ? "Connecting..." : (appState.isConnected ? "Select Connection" : "Connection failed - click to retry or choose another"))
                
                // Region selector (always visible when connected)
                if appState.currentConnection != nil {
                    Menu {
                        Picker("Region", selection: $appState.selectedRegion) {
                            ForEach(RegionHelper.shared.groupedRegions) { group in
                                Section(group.name) {
                                    ForEach(group.regions, id: \.self) { region in
                                        Text(RegionHelper.shared.regionName(region)).tag(region)
                                    }
                                }
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label(RegionHelper.shared.regionName(appState.selectedRegion), systemImage: "globe.americas.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .menuIndicator(.hidden)
                    .help("Select Region")
                }
                
                // Refresh button
                Button {
                    Task { await appState.loadData() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                        .symbolEffect(.rotate, isActive: appState.isLoading)
                }
                .keyboardShortcut("r", modifiers: [.command])
                .help("Refresh (⌘R)")
                .disabled(appState.currentConnection == nil)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddParameterSheet(
                pathPrefix: newValuePathPrefix,
                onAdd: { name, value, type in
                    Task {
                        await appState.addParameter(path: newValuePathPrefix + name, value: value, type: type)
                    }
                }
            )
        }
        .sheet(isPresented: $showingSettings) {
            ConnectionPickerSheet(
                connectionStore: connectionStore,
                currentConnectionId: appState.currentConnection?.id,
                onConnect: { connection in
                    lastConnectWasFromSheet = true
                    Task { await appState.connect(to: connection) }
                }
            )
        }
        .onChange(of: showingSettings) { _, isShowing in
            guard !isShowing else { return }
            defer { lastConnectWasFromSheet = false }
            // Skip reconnect check if the sheet already triggered a connect
            guard !lastConnectWasFromSheet else { return }
            guard let currentId = appState.currentConnection?.id else { return }
            if let updatedConnection = connectionStore.connection(for: currentId) {
                if updatedConnection != appState.currentConnection {
                    Task {
                        await appState.connect(to: updatedConnection)
                        if appState.isConnected {
                            appState.showToast("Reconnected with updated settings")
                        }
                    }
                }
            } else {
                appState.disconnect()
                appState.showToast("Connection was deleted")
            }
        }
        .background {
            // Hidden button for CMD+1 sidebar toggle
            Button("") {
                withAnimation {
                    columnVisibility = columnVisibility == .all ? .detailOnly : .all
                }
            }
            .keyboardShortcut("1", modifiers: [.command])
            .opacity(0)

            // Hidden button for CMD+, settings
            Button("") {
                showingSettings = true
            }
            .keyboardShortcut(",", modifiers: [.command])
            .opacity(0)

            // Hidden button for CMD+F search
            Button("") {
                showingSearch = true
            }
            .keyboardShortcut("f", modifiers: [.command])
            .opacity(0)
        }
        .onChange(of: appState.selectedRegion) { _, newRegion in
            guard appState.currentConnection != nil else { return }
            let previousPath = selection.flatMap { findNode(id: $0, nodes: appState.rootNodes)?.fullPath }
            Task {
                await appState.loadData()
                // Try to restore selection to same path in new environment
                if let path = previousPath, let node = appState.findNodeByPath(path) {
                    selection = node.id
                } else {
                    selection = nil
                }
                // Show toast
                appState.showToast("Switched to region: \(newRegion)")
            }
        }
    }
    
    func findNode(id: String, nodes: [ConfigNode]) -> ConfigNode? {
        for node in nodes {
            if node.id == id { return node }
            if let children = node.children, let found = findNode(id: id, nodes: children) {
                return found
            }
        }
        return nil
    }
    
    func findParentId(for targetId: String, in nodes: [ConfigNode], parentId: String? = nil) -> String? {
        for node in nodes {
            if node.id == targetId {
                return parentId
            }
            if let children = node.children {
                if let found = findParentId(for: targetId, in: children, parentId: node.id) {
                    return found
                }
            }
        }
        return nil
    }
}

// MARK: - Root Folder View

struct RootFolderView: View {
    @Binding var selection: String?
    @EnvironmentObject var appState: AppState
    
    private var children: [ConfigNode] {
        appState.rootNodes
    }
    
    private var parameterCount: Int {
        children.filter { $0.isLeaf }.count
    }
    
    private var folderCount: Int {
        children.filter { !$0.isLeaf }.count
    }
    
    private var totalDescendants: Int {
        children.reduce(0) { total, child in
            child.isLeaf ? total + 1 : total + child.totalLeafCount
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Root breadcrumb indicator
            HStack(spacing: 4) {
                Image(systemName: "house.fill")
                    .font(.caption)
                    .foregroundStyle(.primary)
                Text("Root")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                
                if let connection = appState.currentConnection {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Image(systemName: connection.type.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(connection.name)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            
            if appState.isLoading && children.isEmpty {
                // Loading state
                VStack {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading parameters...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if children.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "tray")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No Parameters")
                        .font(.title2.weight(.semibold))
                    Text("Click the Add button to create your first parameter.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Content
                VStack(alignment: .leading, spacing: 16) {
                    // Colored Statistics Grid
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
                            color: .secondary,
                            count: totalDescendants,
                            label: "Total Parameters"
                        )
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                
                // Children List Card
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
}


// MARK: - Add Parameter Sheet

// MARK: - Shortcuts Popover

struct ShortcutsPopover: View {
    private let shortcuts: [(keys: String, description: String)] = [
        ("⌘ H", "Go to Home"),
        ("⎋", "Revert & Go Back to Parent"),
        ("⌘ 1", "Toggle Sidebar"),
        ("⌘ T", "New Tab"),
        ("⇧⌘ N", "Add New Parameter"),
        ("⌘ F", "Search Parameters"),
        ("⌘ R", "Refresh"),
        ("⌘ S", "Save Changes"),
        ("⌘ ,", "Settings"),
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "keyboard")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Keyboard Shortcuts")
                    .font(.headline)
            }
            
            Divider()
            
            // Shortcuts list
            VStack(alignment: .leading, spacing: 10) {
                ForEach(shortcuts, id: \.keys) { shortcut in
                    HStack {
                        Text(shortcut.keys)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(width: 60, alignment: .leading)
                        
                        Text(shortcut.description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                    }
                }
            }
        }
        .padding()
        .frame(width: 280)
        .background(.ultraThinMaterial)
    }
}

enum ParameterType: String, CaseIterable {
    case string = "String"
    case secureString = "SecureString"
}

struct AddParameterSheet: View {
    let pathPrefix: String
    let onAdd: (String, String, ParameterType) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var parameterName: String = ""
    @State private var parameterValue: String = ""
    @State private var parameterType: ParameterType = .string
    @FocusState private var isNameFocused: Bool

    private var isValid: Bool {
        !parameterName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                // Path: prefix on its own line ending with /, name field below it.
                // Both left-aligned in monospaced so they read as one continuous path.
                Section("Path") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pathPrefix)
                            .foregroundStyle(.secondary)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.head)
                        TextField("", text: $parameterName)
                            .font(.system(.body, design: .monospaced))
                            .focused($isNameFocused)
                    }
                    .padding(.vertical, 2)
                }

                // Type: LabeledContent works fine here — segmented picker is a
                // compact single-row control that fits naturally in the right column.
                Section {
                    LabeledContent("Type") {
                        Picker("Type", selection: $parameterType) {
                            ForEach(ParameterType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 240)
                    }
                }

                // Value: section header as label so the TextEditor spans the full
                // row width and anchors top-left instead of being pushed right.
                Section("Value") {
                    TextEditor(text: $parameterValue)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 100)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("New Parameter")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Parameter") {
                        onAdd(parameterName, parameterValue, parameterType)
                        dismiss()
                    }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
                }
            }
        }
        .frame(minWidth: 460)
        .onAppear { isNameFocused = true }
    }
}
