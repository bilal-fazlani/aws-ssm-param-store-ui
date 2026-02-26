import SwiftUI
import Combine
import AWSSSM

@MainActor
class AppState: ObservableObject {
    @Published var rootNodes: [ConfigNode] = []
    @Published var selectedNodeId: String?
    
    // Connection management
    @Published var currentConnection: Connection?
    @Published var pendingConnection: Connection?  // Connection being attempted
    @Published var selectedRegion: String = "eu-west-1"
    
    // Removed hardcoded availableRegions in favor of RegionHelper


    @Published var lastUpdated: Date?
    @Published var isLoading: Bool = false
    @Published var isConnecting: Bool = false  // True while attempting connection
    @Published var valuesLoadProgress: (loaded: Int, total: Int)? = nil  // Phase 2 progress
    @Published var errorMessage: String?
    @Published var toastMessage: String?
    @Published var isConnected: Bool = false
    @Published var availableUpdateVersion: String?
    
    private let service = SSMService()
    private var toastTask: Task<Void, Never>?
    let connectionStore = ConnectionStore.shared
    
    init() {
        // Region will be set when a connection is selected
    }
    
    // MARK: - Connection Management
    
    func connect(to connection: Connection) async {
        // Update connection immediately (show new name/icon right away)
        currentConnection = connection
        selectedRegion = connection.region
        pendingConnection = nil
        isConnecting = true
        isLoading = true
        isConnected = false
        errorMessage = nil
        
        // Clear old data immediately to avoid showing stale content
        rootNodes = []
        
        do {
            // Get credentials — single Touch ID prompt covers both secret and session token
            let secretKey: String?
            let sessionToken: String?
            if connection.type == .credentials {
                let credentials = await connectionStore.fetchCredentialsForConnect(connection)
                secretKey   = credentials.secretKey
                sessionToken = credentials.sessionToken
            } else {
                secretKey = nil
                sessionToken = nil
            }

            try await service.configure(with: connection, secretKey: secretKey, sessionToken: sessionToken)
            try await performTwoPhaseLoad()

            self.connectionStore.setLastConnection(connection)
            self.lastUpdated = Date()
            self.isConnected = true
            
        } catch {
            print("Connection Error: \(error)")
            // Keep showing the failed connection (don't revert to previous)
            // isConnected stays false to show error state
            self.isConnected = false
            
            // Show appropriate error message
            switch connection.type {
            case .ssoProfile:
                self.errorMessage = "Connection failed. Check your network or run: aws sso login --profile \(connection.profileName ?? "default")"
            case .localstack:
                self.errorMessage = "Connection failed. Check your network and ensure LocalStack is running at \(connection.effectiveEndpoint)."
            case .credentials:
                self.errorMessage = "Connection failed. Check your credentials and network."
            }
        }
        
        isConnecting = false
        isLoading = false
    }
    
    /// Refresh connection with updated settings (used when editing current connection)
    func refreshCurrentConnection() async {
        guard let connection = currentConnection else { return }
        
        // Re-fetch the connection from store in case it was updated
        if let updatedConnection = connectionStore.connection(for: connection.id) {
            await connect(to: updatedConnection)
        }
    }
    
    func disconnect() {
        currentConnection = nil
        isConnected = false
        rootNodes = []
        lastUpdated = nil
    }
    
    // MARK: - Data Loading
    
    func loadData() async {
        guard let connection = currentConnection else {
            errorMessage = "No connection selected"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Get credentials from keychain if needed
            let secretKey: String?
            let sessionToken: String?
            if connection.type == .credentials {
                secretKey = connectionStore.secretKey(for: connection)
                sessionToken = connectionStore.sessionToken(for: connection)
            } else {
                secretKey = nil
                sessionToken = nil
            }

            // Create a connection with the current region (which may have been changed in toolbar)
            var effectiveConnection = connection
            effectiveConnection.region = selectedRegion

            try await service.configure(with: effectiveConnection, secretKey: secretKey, sessionToken: sessionToken)
            try await performTwoPhaseLoad()

            self.lastUpdated = Date()
            self.isConnected = true
        } catch {
            print("Load Error: \(error)")
            self.isConnected = false
            
            if let connection = currentConnection {
                switch connection.type {
                case .ssoProfile:
                    self.errorMessage = "Connection failed. Check your network or run: aws sso login --profile \(connection.profileName ?? "default")"
                case .localstack:
                    self.errorMessage = "Connection failed. Check your network and ensure LocalStack is running at \(connection.effectiveEndpoint)."
                case .credentials:
                    self.errorMessage = "Connection failed. Check your credentials and network."
                }
            } else {
                self.errorMessage = "Connection failed: \(error.localizedDescription)"
            }
        }
        isLoading = false
    }
    
    func save(nodeId: String, newValue: String) async {
        // Find node by ID first
        // Since ConfigNode is a struct, we modify the tree in place
        // But recursively finding and modifying a struct in an array is tricky.
        // We will implement a helper to update the tree.
        
        do {
            // Optimistic update
            if let node = findNode(id: nodeId, nodes: rootNodes) {
                 _ = try await service.updateParameter(name: node.fullPath, value: newValue)
                 
                 // Success - update tree
                 updateNode(id: nodeId, in: &rootNodes) { n in
                     n.serverValue = newValue
                     n.value = newValue
                     n.isDirty = false
                     n.lastModified = Date()
                 }
            }
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }
    
    // Helper to find node (copy)
    func findNode(id: String, nodes: [ConfigNode]) -> ConfigNode? {
        for node in nodes {
            if node.id == id { return node }
            if let children = node.children, let found = findNode(id: id, nodes: children) {
                return found
            }
        }
        return nil
    }
    
    // Helper to update node in place
    func updateNode(id: String, in nodes: inout [ConfigNode], transform: (inout ConfigNode) -> Void) {
        for i in 0..<nodes.count {
            if nodes[i].id == id {
                transform(&nodes[i])
                return
            }
            if nodes[i].children != nil {
                updateNode(id: id, in: &nodes[i].children!, transform: transform)
            }
        }
    }
    
    // Helper to update local value (from Editor)
    func updateLocalValue(id: String, value: String) {
        updateNode(id: id, in: &rootNodes) { n in
            n.value = value
            n.isDirty = (n.value != n.serverValue)
        }
    }
    
    // MARK: - Two-Phase Loading

    // Phase 1: DescribeParameters (50/page) → populate sidebar with metadata immediately.
    // Phase 2: GetParameters in parallel batches of 10 → fill in values concurrently.
    private func performTwoPhaseLoad() async throws {
        let service = self.service  // capture actor ref for non-isolated task group closures
        var allNames: [String] = []
        var seenPaths = Set<String>()

        // ── Phase 1: stream metadata, insert nodes as each page arrives ─────────
        let metadataStream = try await service.describeAllParameters()
        for try await batch in metadataStream {
            for meta in batch {
                guard let fullPath = meta.name, !fullPath.isEmpty else { continue }
                allNames.append(fullPath)
                seenPaths.insert(fullPath)
                // Only insert if not already present — preserves loaded values on refresh
                if findNode(id: fullPath, nodes: rootNodes) == nil {
                    let leafName = String(fullPath.split(separator: "/").last ?? Substring(fullPath))
                    var leafNode = ConfigNode(name: leafName, fullPath: fullPath, value: nil)
                    leafNode.type = meta.type?.rawValue
                    leafNode.lastModified = meta.lastModifiedDate
                    leafNode.isValueLoaded = false
                    insertNode(leafNode, into: &rootNodes)
                }
            }
        }

        // Remove leaf nodes deleted from AWS since the last load
        pruneNodes(notIn: seenPaths, from: &rootNodes)

        // Phase 1 done — sidebar is fully populated; stop the main loading indicator
        isLoading = false
        isConnected = true

        guard !allNames.isEmpty else { return }

        // ── Phase 2: parallel value fetches ─────────────────────────────────────
        let batches = stride(from: 0, to: allNames.count, by: 10).map {
            Array(allNames[$0..<min($0 + 10, allNames.count)])
        }
        valuesLoadProgress = (loaded: 0, total: allNames.count)

        await withTaskGroup(of: [SSMClientTypes.Parameter].self) { group in
            for batch in batches {
                group.addTask { (try? await service.fetchParameterValues(names: batch)) ?? [] }
            }
            for await parameters in group {
                for param in parameters {
                    guard let name = param.name, let value = param.value else { continue }
                    updateNode(id: name, in: &rootNodes) { n in
                        n.value = value
                        n.serverValue = value
                        n.isValueLoaded = true
                        if let date = param.lastModifiedDate { n.lastModified = date }
                    }
                }
                valuesLoadProgress?.loaded += parameters.count
            }
        }
        valuesLoadProgress = nil
    }

    // Remove leaf nodes whose paths are no longer returned by the server (handles deletions).
    // Folders that become empty are also pruned.
    private func pruneNodes(notIn seenPaths: Set<String>, from nodes: inout [ConfigNode]) {
        var result: [ConfigNode] = []
        for var node in nodes {
            if node.isLeaf {
                if seenPaths.contains(node.fullPath) || node.isPending {
                    result.append(node)
                }
            } else {
                if node.children != nil {
                    pruneNodes(notIn: seenPaths, from: &node.children!)
                }
                if !(node.children?.isEmpty ?? true) {
                    result.append(node)
                }
            }
        }
        nodes = result
    }

    // Add a new parameter (optimistic: inserts into tree immediately, rolls back on failure)
    func addParameter(path: String, value: String, type: ParameterType = .string) async {
        var optimisticNode = ConfigNode(
            name: String(path.split(separator: "/").last ?? Substring(path)),
            fullPath: path,
            value: value
        )
        optimisticNode.serverValue = value
        optimisticNode.type = type.rawValue
        optimisticNode.isPending = true
        optimisticNode.lastModified = Date()

        insertNode(optimisticNode, into: &rootNodes)

        do {
            let createdDate = try await service.createParameter(name: path, value: value, isSecure: type == .secureString)
            updateNode(id: path, in: &rootNodes) { n in
                n.isPending = false
                n.lastModified = createdDate
            }
            showToast("Parameter added")
        } catch {
            removeNode(path: path, from: &rootNodes)
            errorMessage = "Failed to add \"\(path.split(separator: "/").last.map(String.init) ?? path)\": \(error.localizedDescription)"
            print("Add parameter error: \(error)")
        }
    }

    // Delete a parameter (optimistic: removes from tree immediately, rolls back on failure)
    func deleteParameter(path: String) async {
        guard let nodeToDelete = findNode(id: path, nodes: rootNodes) else { return }
        removeNode(path: path, from: &rootNodes)
        do {
            try await service.deleteParameter(name: path)
            showToast("Parameter deleted")
        } catch {
            insertNode(nodeToDelete, into: &rootNodes)
            errorMessage = "Failed to delete \"\(nodeToDelete.name)\": \(error.localizedDescription)"
            print("Delete parameter error: \(error)")
        }
    }

    // Delete a folder (removes entire subtree optimistically, fires leaf deletes concurrently)
    func deleteFolder(_ folder: ConfigNode) async {
        var paths: [String] = []
        collectLeafPaths(folder, into: &paths)
        removeNode(path: folder.fullPath, from: &rootNodes)

        var failedCount = 0
        await withTaskGroup(of: Bool.self) { group in
            for path in paths {
                group.addTask {
                    do {
                        try await self.service.deleteParameter(name: path)
                        return true
                    } catch {
                        return false
                    }
                }
            }
            for await success in group {
                if !success { failedCount += 1 }
            }
        }

        if failedCount == 0 {
            showToast("Folder deleted (\(paths.count) parameter\(paths.count == 1 ? "" : "s"))")
        } else {
            errorMessage = "\(failedCount) deletion(s) failed. Refreshing..."
            await loadData()
        }
    }

    private func collectLeafPaths(_ node: ConfigNode, into paths: inout [String]) {
        if node.isLeaf {
            paths.append(node.fullPath)
        } else {
            for child in node.children ?? [] {
                collectLeafPaths(child, into: &paths)
            }
        }
    }

    // Inserts a node into the tree at the correct sorted position, creating intermediate folders as needed
    @discardableResult
    private func insertNode(_ newNode: ConfigNode, into nodes: inout [ConfigNode], currentPath: String = "") -> Bool {
        let components = newNode.fullPath.split(separator: "/").map(String.init)
        return insertComponents(components, newNode: newNode, into: &nodes, currentPath: currentPath)
    }

    private func insertComponents(_ components: [String], newNode: ConfigNode, into nodes: inout [ConfigNode], currentPath: String) -> Bool {
        guard let head = components.first else { return false }
        let tail = Array(components.dropFirst())
        let nodePath = currentPath == "/" ? "/\(head)" : "\(currentPath)/\(head)"

        if tail.isEmpty {
            guard !nodes.contains(where: { $0.id == nodePath }) else { return true }
            let insertIndex = nodes.firstIndex(where: { $0.name > head }) ?? nodes.endIndex
            nodes.insert(newNode, at: insertIndex)
            return true
        } else {
            if let index = nodes.firstIndex(where: { $0.id == nodePath }) {
                if nodes[index].children == nil { nodes[index].children = [] }
                return insertComponents(tail, newNode: newNode, into: &nodes[index].children!, currentPath: nodePath)
            } else {
                var folder = ConfigNode(name: head, fullPath: nodePath, children: [])
                _ = insertComponents(tail, newNode: newNode, into: &folder.children!, currentPath: nodePath)
                let insertIndex = nodes.firstIndex(where: { $0.name > head }) ?? nodes.endIndex
                nodes.insert(folder, at: insertIndex)
                return true
            }
        }
    }

    // Removes a node by fullPath, prunes empty intermediate folders, returns removed node for rollback
    @discardableResult
    private func removeNode(path: String, from nodes: inout [ConfigNode]) -> ConfigNode? {
        for i in 0..<nodes.count {
            if nodes[i].fullPath == path {
                let removed = nodes[i]
                nodes.remove(at: i)
                return removed
            }
            if nodes[i].children != nil {
                if let removed = removeNode(path: path, from: &nodes[i].children!) {
                    if nodes[i].children!.isEmpty { nodes.remove(at: i) }
                    return removed
                }
            }
        }
        return nil
    }
    
    // MARK: - Update Check

    func checkForUpdates() {
        Task {
            let checker = UpdateCheckerService()
            availableUpdateVersion = await checker.checkForUpdate()
        }
    }

    // MARK: - Toast
    
    func showToast(_ message: String, duration: TimeInterval = 2.0) {
        // Cancel any existing toast dismissal
        toastTask?.cancel()
        
        toastMessage = message
        
        toastTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if !Task.isCancelled {
                toastMessage = nil
            }
        }
    }
    
    // MARK: - Path Lookup
    
    func findNodeByPath(_ path: String) -> ConfigNode? {
        findNodeByPath(path, in: rootNodes)
    }
    
    private func findNodeByPath(_ path: String, in nodes: [ConfigNode]) -> ConfigNode? {
        for node in nodes {
            if node.fullPath == path {
                return node
            }
            if let children = node.children, let found = findNodeByPath(path, in: children) {
                return found
            }
        }
        return nil
    }
}
