import Foundation
import SwiftUI

struct ConfigNode: Identifiable, Hashable, Equatable {
    let id: String
    let name: String
    let fullPath: String
    
    // Leaf properties
    var value: String?
    var serverValue: String?
    var lastModified: Date?
    var type: String? // String, StringList, SecureString
    var description: String?

    // Metadata from DescribeParameters (Phase 1)
    var version: Int?
    var arn: String?
    var tier: String?              // "Standard", "Advanced", "Intelligent-Tiering"
    var lastModifiedUser: String?
    var keyId: String?             // KMS key alias/ID for SecureString
    var dataType: String?          // e.g. "text", "aws:ec2:image"
    var allowedPattern: String?
    
    // Conflict / Edit state
    var isDirty: Bool = false

    // Optimistic UI state
    var isPending: Bool = false    // true while an AWS add is in flight
    var isValueLoaded: Bool = true // false while Phase 2 value fetch is in flight

    // Tree structure
    var children: [ConfigNode]?
    
    var isLeaf: Bool {
        children == nil
    }

    /// True when this node corresponds to an actual SSM parameter (as opposed to a synthetic
    /// path-prefix folder). A node can be both a value node AND have children when its path is
    /// also a prefix of other parameters (e.g. `/a/b` exists alongside `/a/b/c`).
    var isValueNode: Bool {
        value != nil || serverValue != nil || isValueLoaded == false
    }

    /// Total count of all descendants (folders + parameters) at any depth.
    var totalDescendantCount: Int {
        guard let children = children else { return 0 }
        return children.reduce(0) { count, child in
            child.isLeaf ? count + 1 : count + 1 + child.totalDescendantCount
        }
    }

    /// Total count of leaf parameters at any depth (excludes intermediate folders).
    /// Hybrid nodes (path is both a parameter and a namespace prefix) count as +1 for their own value.
    var totalLeafCount: Int {
        guard let children = children else { return 0 }
        let childCount = children.reduce(0) { count, child in
            child.isLeaf ? count + 1 : count + child.totalLeafCount
        }
        return isValueNode ? childCount + 1 : childCount
    }

    /// All SSM parameter paths at or below this node. For a folder this is every
    /// descendant leaf (and the node itself if it's a hybrid); for a plain leaf
    /// this is just `[fullPath]`. Same traversal `AppState.collectLeafPaths`
    /// uses internally when fanning out deletes, exposed here so views can
    /// preview what a delete will touch without reaching into AppState.
    var allLeafPaths: [String] {
        if isLeaf { return [fullPath] }
        var paths: [String] = []
        if isValueNode { paths.append(fullPath) }
        for child in children ?? [] {
            paths.append(contentsOf: child.allLeafPaths)
        }
        return paths
    }
    
    init(name: String, fullPath: String, value: String? = nil, children: [ConfigNode]? = nil) {
        self.id = fullPath
        self.name = name
        self.fullPath = fullPath
        self.value = value
        self.serverValue = value
        self.children = children
    }
    
    static func buildTree(from parameters: [(path: String, value: String, type: String?, lastModified: Date?, description: String?)]) -> [ConfigNode] {
        var rootChildren: [ConfigNode] = []
        
        // Sort by path to ensure deterministic order
        let sortedParams = parameters.sorted { $0.path < $1.path }
        
        for param in sortedParams {
            let components = param.path.split(separator: "/").map(String.init)
            insert(components: components, param: param, nodes: &rootChildren, currentPath: "")
        }
        sortFoldersFirst(&rootChildren)
        return rootChildren
    }

    /// Recursively sorts children so folders appear before leaves, alphabetically within each group.
    private static func sortFoldersFirst(_ nodes: inout [ConfigNode]) {
        nodes.sort { a, b in
            if a.isLeaf != b.isLeaf { return !a.isLeaf }
            return a.name < b.name
        }
        for i in nodes.indices where !nodes[i].isLeaf {
            if nodes[i].children != nil {
                sortFoldersFirst(&nodes[i].children!)
            }
        }
    }
    
    private static func insert(components: [String], param: (path: String, value: String, type: String?, lastModified: Date?, description: String?), nodes: inout [ConfigNode], currentPath: String) {
        guard let head = components.first else { return }
        let tail = Array(components.dropFirst())
        
        let nodePath = currentPath == "/" ? "/\(head)" : "\(currentPath)/\(head)"
        
        if let index = nodes.firstIndex(where: { $0.name == head }) {
            // Modify existing struct in place
            if tail.isEmpty {
                nodes[index].value = param.value
                nodes[index].serverValue = param.value
                nodes[index].type = param.type
                nodes[index].lastModified = param.lastModified
                nodes[index].description = param.description
            } else {
                if nodes[index].children == nil { nodes[index].children = [] }
                insert(components: tail, param: param, nodes: &nodes[index].children!, currentPath: nodePath)
            }
        } else {
            if tail.isEmpty {
                // Create leaf
                var newNode = ConfigNode(name: head, fullPath: nodePath, value: param.value)
                newNode.type = param.type
                newNode.lastModified = param.lastModified
                newNode.description = param.description
                nodes.append(newNode)
            } else {
                // Create folder
                var newNode = ConfigNode(name: head, fullPath: nodePath, children: [])
                insert(components: tail, param: param, nodes: &newNode.children!, currentPath: nodePath)
                nodes.append(newNode)
            }
        }
    }
    
    // Merge logic for Structs
    mutating func merge(with newNode: ConfigNode) {
        if self.isLeaf && newNode.isLeaf {
            self.lastModified = newNode.lastModified
            self.type = newNode.type
            self.description = newNode.description
            self.version = newNode.version
            self.arn = newNode.arn
            self.tier = newNode.tier
            self.lastModifiedUser = newNode.lastModifiedUser
            self.keyId = newNode.keyId
            self.dataType = newNode.dataType
            self.allowedPattern = newNode.allowedPattern

            if newNode.isValueLoaded {
                // Incoming node has a real value — accept it
                self.serverValue = newNode.serverValue
                self.isValueLoaded = true
                if !self.isDirty {
                    self.value = newNode.value
                } else {
                    if self.value == self.serverValue { self.isDirty = false }
                }
            } else {
                // Incoming node is metadata-only; preserve our value if we already have one
                if !self.isValueLoaded { self.serverValue = newNode.serverValue }
            }
        } else {
             // Merge children
             if self.children == nil { self.children = [] }
             if let newChildren = newNode.children {
                 ConfigNode.mergeLists(existing: &self.children!, new: newChildren)
             }
        }
    }

    static func mergeLists(existing: inout [ConfigNode], new: [ConfigNode]) {
        var usedIds = Set<String>()
        
        for newNode in new {
            usedIds.insert(newNode.id)
            if let index = existing.firstIndex(where: { $0.id == newNode.id }) {
                existing[index].merge(with: newNode)
            } else {
                existing.append(newNode)
            }
        }
        
        // Remove deleted nodes, but preserve nodes with in-flight optimistic adds
        existing.removeAll { !usedIds.contains($0.id) && !$0.isPending }
        
        // Re-sort: folders first, then alphabetically within each group
        existing.sort { a, b in
            if a.isLeaf != b.isLeaf { return !a.isLeaf }
            return a.name < b.name
        }
    }
}
