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

    /// Total count of all descendants (folders + parameters) at any depth.
    var totalDescendantCount: Int {
        guard let children = children else { return 0 }
        return children.reduce(0) { count, child in
            child.isLeaf ? count + 1 : count + 1 + child.totalDescendantCount
        }
    }

    /// Total count of leaf parameters at any depth (excludes intermediate folders).
    var totalLeafCount: Int {
        guard let children = children else { return 0 }
        return children.reduce(0) { count, child in
            child.isLeaf ? count + 1 : count + child.totalLeafCount
        }
    }
    
    init(name: String, fullPath: String, value: String? = nil, children: [ConfigNode]? = nil) {
        self.id = fullPath
        self.name = name
        self.fullPath = fullPath
        self.value = value
        self.serverValue = value
        self.children = children
    }
    
    static func buildTree(from parameters: [(path: String, value: String, type: String?, lastModified: Date?)]) -> [ConfigNode] {
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
    
    private static func insert(components: [String], param: (path: String, value: String, type: String?, lastModified: Date?), nodes: inout [ConfigNode], currentPath: String) {
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
