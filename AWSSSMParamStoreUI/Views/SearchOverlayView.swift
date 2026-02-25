import SwiftUI

// MARK: - Search Result Model

enum SearchMatchKind {
    case exactName    // node.name == query (case-insensitive)
    case partialName  // node.name contains query
    case path         // fullPath contains query but name does not (leaves only)
    case value        // value contains query (non-SecureString leaves only)
}

enum SearchDisplayCategory: Equatable {
    case exact, name, inPath, value

    var label: String {
        switch self {
        case .exact:  return "Exact Match"
        case .name:   return "Name"
        case .inPath: return "In Path"
        case .value:  return "Value"
        }
    }
}

struct SearchResult: Identifiable {
    let id: String
    let node: ConfigNode
    let kind: SearchMatchKind
    let isFolder: Bool
    let valueExcerpt: String?

    init(id: String, node: ConfigNode, kind: SearchMatchKind, isFolder: Bool = false, valueExcerpt: String? = nil) {
        self.id = id
        self.node = node
        self.kind = kind
        self.isFolder = isFolder
        self.valueExcerpt = valueExcerpt
    }

    var displayCategory: SearchDisplayCategory {
        switch kind {
        case .exactName:  return .exact
        case .partialName: return .name
        case .path:        return .inPath
        case .value:       return .value
        }
    }
}

// MARK: - Search Overlay

struct SearchOverlayView: View {
    @Binding var isPresented: Bool
    let rootNodes: [ConfigNode]
    let onSelect: (String) -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    private var results: [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let q = query.lowercased()

        // Bucket 1: exact folder name
        var exactFolderMatches: [SearchResult] = []
        // Bucket 2: exact leaf name
        var exactLeafMatches: [SearchResult] = []
        // Bucket 3: folder name contains (partial)
        var partialFolderMatches: [SearchResult] = []
        // Bucket 4: leaf name contains (partial)
        var partialLeafMatches: [SearchResult] = []
        // Bucket 5: leaf path contains (name does NOT match), sorted by match depth
        var pathMatches: [SearchResult] = []
        // Bucket 6: leaf value contains (non-SecureString)
        var valueMatches: [SearchResult] = []

        // Folders only participate in name buckets (exact + partial)
        for node in collectFolders(rootNodes) {
            let nameLower = node.name.lowercased()
            if nameLower == q {
                exactFolderMatches.append(SearchResult(id: node.id, node: node, kind: .exactName, isFolder: true))
            } else if nameLower.contains(q) {
                partialFolderMatches.append(SearchResult(id: node.id, node: node, kind: .partialName, isFolder: true))
            }
        }

        for node in collectLeaves(rootNodes) {
            let nameLower = node.name.lowercased()
            if nameLower == q {
                exactLeafMatches.append(SearchResult(id: node.id, node: node, kind: .exactName))
            } else if nameLower.contains(q) {
                partialLeafMatches.append(SearchResult(id: node.id, node: node, kind: .partialName))
            } else if node.fullPath.lowercased().contains(q) {
                pathMatches.append(SearchResult(id: node.id, node: node, kind: .path))
            } else if node.type != "SecureString",
                      let value = node.value,
                      value.lowercased().contains(q) {
                let excerpt = makeExcerpt(value: value, query: q)
                valueMatches.append(SearchResult(id: node.id, node: node, kind: .value, valueExcerpt: excerpt))
            }
        }

        exactFolderMatches.sort  { $0.node.fullPath < $1.node.fullPath }
        exactLeafMatches.sort    { $0.node.fullPath < $1.node.fullPath }
        partialFolderMatches.sort { $0.node.fullPath < $1.node.fullPath }
        partialLeafMatches.sort  { $0.node.fullPath < $1.node.fullPath }
        // Path bucket: sort by depth of matching component, then alphabetically
        pathMatches.sort { a, b in
            let da = pathMatchDepth(fullPath: a.node.fullPath, query: q)
            let db = pathMatchDepth(fullPath: b.node.fullPath, query: q)
            return da != db ? da < db : a.node.fullPath < b.node.fullPath
        }
        valueMatches.sort { $0.node.fullPath < $1.node.fullPath }

        return exactFolderMatches + exactLeafMatches
             + partialFolderMatches + partialLeafMatches
             + pathMatches + valueMatches
    }

    var body: some View {
        let currentResults = results

        ZStack(alignment: .top) {
            // ── Liquid Glass background ──
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.25).ignoresSafeArea())

            // ── Main content column ──
            VStack(spacing: 0) {

                // Search bar — always at this position, never moves
                HStack(spacing: 14) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.secondary)

                    TextField("Search parameters…", text: $query)
                        .font(.title2)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        .onSubmit { confirmSelection(in: currentResults) }
                        .onKeyPress(.escape) { dismiss(); return .handled }
                        .onKeyPress(.upArrow) { moveSelection(by: -1, in: currentResults); return .handled }
                        .onKeyPress(.downArrow) { moveSelection(by: 1, in: currentResults); return .handled }

                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.separator, lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
                .padding(.horizontal, 48)
                .padding(.top, 80)

                // ── Content area — ZStack keeps search bar pinned above ──
                ZStack {
                    if !currentResults.isEmpty {
                        let categories = Set(currentResults.map { $0.displayCategory })
                        let showHeaders = categories.count > 1
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 0, pinnedViews: []) {
                                    ForEach(Array(currentResults.enumerated()), id: \.element.id) { index, result in
                                        // Show category header at the start of each new category
                                        if showHeaders {
                                            let cat = result.displayCategory
                                            if index == 0 || currentResults[index - 1].displayCategory != cat {
                                                sectionHeader(cat.label)
                                            }
                                        }
                                        SearchResultRow(
                                            result: result,
                                            query: query,
                                            isSelected: index == selectedIndex
                                        ) {
                                            onSelect(result.node.id)
                                            dismiss()
                                        }
                                        .id(result.id)
                                    }
                                }
                                .padding(.horizontal, 40)
                                .padding(.vertical, 8)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onChange(of: selectedIndex) { _, newIndex in
                                guard newIndex < currentResults.count else { return }
                                proxy.scrollTo(currentResults[newIndex].id)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 36, weight: .ultraLight))
                                .foregroundStyle(.tertiary)
                            Text("No results for \"\(query)\"")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 14) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 48, weight: .ultraLight))
                                .foregroundStyle(.tertiary)
                            Text("Search by name, path, or value")
                                .font(.title3)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // ── Bottom hint bar ──
                HStack(spacing: 14) {
                    if !currentResults.isEmpty {
                        Text("\(currentResults.count) result\(currentResults.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Color.secondary.opacity(0.4)
                            .frame(width: 1, height: 12)
                    }
                    keyHint("↑↓", label: "navigate")
                    keyHint("↩", label: "select")
                    keyHint("esc", label: "dismiss")
                }
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Delay one run-loop pass so the transition completes before focusing
            DispatchQueue.main.async { isSearchFocused = true }
        }
        .onChange(of: query) { _, _ in selectedIndex = 0 }
    }

    // MARK: - Section Header

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .kerning(0.5)
            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(height: 0.5)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Key Hint Chip

    @ViewBuilder
    private func keyHint(_ key: String, label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Helpers

    private func dismiss() {
        query = ""
        isPresented = false
    }

    private func confirmSelection(in currentResults: [SearchResult]) {
        guard !currentResults.isEmpty, selectedIndex < currentResults.count else { return }
        onSelect(currentResults[selectedIndex].node.id)
        dismiss()
    }

    private func moveSelection(by delta: Int, in currentResults: [SearchResult]) {
        let newIndex = selectedIndex + delta
        guard newIndex >= 0 && newIndex < currentResults.count else { return }
        selectedIndex = newIndex
    }

    private func collectLeaves(_ nodes: [ConfigNode]) -> [ConfigNode] {
        nodes.flatMap { node in
            node.isLeaf ? [node] : collectLeaves(node.children ?? [])
        }
    }

    private func collectFolders(_ nodes: [ConfigNode]) -> [ConfigNode] {
        nodes.flatMap { node in
            node.isLeaf ? [] : [node] + collectFolders(node.children ?? [])
        }
    }

    /// Returns the index of the first path component containing the query.
    /// Lower = closer to root = higher priority in path bucket.
    private func pathMatchDepth(fullPath: String, query: String) -> Int {
        let components = fullPath.lowercased().split(separator: "/")
        return components.firstIndex(where: { $0.contains(query) }) ?? components.count
    }

    private func makeExcerpt(value: String, query: String) -> String {
        guard let range = value.lowercased().range(of: query) else {
            return String(value.prefix(80))
        }
        let matchStart = value.distance(from: value.startIndex, to: range.lowerBound)
        let contextStart = max(0, matchStart - 25)
        let startIndex = value.index(value.startIndex, offsetBy: contextStart)
        let endOffset = min(value.count, contextStart + 80)
        let endIndex = value.index(value.startIndex, offsetBy: endOffset)
        let excerpt = String(value[startIndex..<endIndex])
        return (contextStart > 0 ? "…" : "") + excerpt + (endOffset < value.count ? "…" : "")
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let result: SearchResult
    let query: String
    let isSelected: Bool
    let onTap: () -> Void

    private var iconColor: Color {
        if result.isFolder { return .blue }
        return result.node.type == "SecureString" ? .red : .gray
    }

    private var iconName: String {
        if result.isFolder { return "folder.fill" }
        return result.node.type == "SecureString" ? "lock.fill" : "doc.text.fill"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    // Icon badge
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(iconColor.gradient)
                            .frame(width: 24, height: 24)
                        Image(systemName: iconName)
                            .foregroundStyle(.white)
                            .font(.system(size: 11, weight: .medium))
                    }

                    // Name — highlight for any name match (exact or partial)
                    let isNameMatch = result.kind == .exactName || result.kind == .partialName
                    highlighted(
                        result.node.name,
                        query: isNameMatch ? query : "",
                        font: .body.weight(.medium),
                        color: .primary
                    )

                    Spacer(minLength: 12)

                    // Full path — highlight for name matches (path ends with the name)
                    // and for path matches (match is somewhere in the path)
                    highlighted(
                        result.node.fullPath,
                        query: (isNameMatch || result.kind == .path) ? query : "",
                        font: .callout,
                        color: .secondary
                    )
                    .lineLimit(1)
                    .truncationMode(.head)

                    // Folder: child count badge
                    if result.isFolder {
                        let childCount = result.node.children?.count ?? 0
                        Text("\(childCount)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1), in: Capsule())
                    } else if let type = result.node.type {
                        // Leaf: type badge
                        Text(abbreviateType(type))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }

                // Value excerpt — only for value-match results
                if result.kind == .value, let excerpt = result.valueExcerpt {
                    HStack(spacing: 0) {
                        Spacer().frame(width: 34) // align under name
                        highlighted(excerpt, query: query, font: .system(.caption, design: .monospaced), color: .secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Highlight Helper

    /// Builds an AttributedString with matched substrings rendered in accent color + bold.
    /// Uses AttributedString to avoid the deprecated Text `+` operator on macOS 26.
    private func highlighted(_ text: String, query: String, font: Font, color: Color) -> Text {
        guard !query.isEmpty else { return Text(text).font(font).foregroundStyle(color) }

        let textLower = text.lowercased()
        let queryLower = query.lowercased()
        var attributed = AttributedString()
        var lastEnd = text.startIndex
        var searchRange = text.startIndex..<text.endIndex
        var anyMatch = false

        while let range = textLower.range(of: queryLower, range: searchRange) {
            anyMatch = true
            let before = String(text[lastEnd..<range.lowerBound])
            if !before.isEmpty {
                var part = AttributedString(before)
                part.font = font
                part.foregroundColor = color
                attributed.append(part)
            }
            var match = AttributedString(String(text[range]))
            match.font = font.bold()
            match.foregroundColor = Color.accentColor
            attributed.append(match)
            lastEnd = range.upperBound
            searchRange = range.upperBound..<text.endIndex
        }

        if !anyMatch { return Text(text).font(font).foregroundStyle(color) }

        let remaining = String(text[lastEnd...])
        if !remaining.isEmpty {
            var part = AttributedString(remaining)
            part.font = font
            part.foregroundColor = color
            attributed.append(part)
        }
        return Text(attributed)
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
