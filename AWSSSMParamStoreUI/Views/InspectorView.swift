import SwiftUI
import AWSSSM

// MARK: - Tab definition

enum InspectorTab: CaseIterable, Hashable {
    case info, history, tags

    var icon: String {
        switch self {
        case .info:    return "info.circle"
        case .history: return "clock"
        case .tags:    return "tag"
        }
    }

    var label: String {
        switch self {
        case .info:    return "Info"
        case .history: return "History"
        case .tags:    return "Tags"
        }
    }
}

// MARK: - Inspector container

struct InspectorView: View {
    let node: ConfigNode
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: InspectorTab = .info

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar — individual pills, no container background
            HStack(spacing: 4) {
                ForEach(InspectorTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.label, systemImage: tab.icon)
                            .labelStyle(.titleAndIcon)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                selectedTab == tab
                                    ? Color.accentColor
                                    : Color.primary.opacity(0.06),
                                in: Capsule()
                            )
                            .foregroundStyle(selectedTab == tab ? Color.white : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .contentShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            switch selectedTab {
            case .info:
                InfoTabView(node: node)
            case .history:
                HistoryTabView(node: node)
            case .tags:
                TagsTabView(node: node)
            }
        }
    }
}

// MARK: - Info tab

struct InfoTabView: View {
    let node: ConfigNode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let version = node.version {
                    metadataRow("Version", value: "v\(version)")
                }
                metadataRow("Type", value: node.type)
                metadataRow("Tier", value: node.tier)
                metadataRow("Data Type", value: node.dataType)
                metadataRow("Last Modified By", value: node.lastModifiedUser.map { shortIAMName($0) })
                if node.type == "SecureString" {
                    metadataRow("KMS Key", value: node.keyId, monospaced: true)
                }
                if let pattern = node.allowedPattern, !pattern.isEmpty {
                    metadataRow("Allowed Pattern", value: pattern, monospaced: true)
                }
                metadataRow("ARN", value: node.arn, monospaced: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func metadataRow(_ label: String, value: String?, monospaced: Bool = false) -> some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
                    .textSelection(.enabled)
                    .lineLimit(4)
            }
        }
    }

    private func shortIAMName(_ arn: String) -> String {
        arn.components(separatedBy: "/").last ?? arn
    }
}

// MARK: - History tab

struct HistoryTabView: View {
    let node: ConfigNode
    @EnvironmentObject var appState: AppState

    private var cache: AppState.ParameterHistoryCache? {
        appState.historyCache[node.fullPath]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Inline header with refresh button — avoids polluting the main window toolbar
            HStack {
                Text("Version History")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await appState.refreshHistory(for: node.fullPath) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Refresh history")
                .disabled(cache?.isLoading == true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            if let error = cache?.error {
                inspectorErrorView(error)
            } else if cache == nil || (cache?.isLoading == true && cache?.entries.isEmpty == true) {
                ProgressView("Loading history…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let entries = cache?.entries, !entries.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Newest first
                        ForEach(Array(entries.reversed().enumerated()), id: \.offset) { _, entry in
                            HistoryEntryRow(entry: entry)
                            Divider()
                        }
                        if cache?.hasMore == true {
                            Button("Load More") {
                                Task { await appState.loadMoreHistory(for: node.fullPath) }
                            }
                            .padding()
                        }
                        if cache?.isLoading == true {
                            ProgressView().padding()
                        }
                    }
                }
            } else {
                Text("No history available")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            Task { await appState.loadHistory(for: node.fullPath, nodeVersion: node.version) }
        }
        .onChange(of: node.id) { _, _ in
            Task { await appState.loadHistory(for: node.fullPath, nodeVersion: node.version) }
        }
    }
}

struct HistoryEntryRow: View {
    let entry: SSMClientTypes.ParameterHistory
    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Primary row: version badge + relative timestamp
            HStack(alignment: .center) {
                Text("v\(entry.version)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if let date = entry.lastModifiedDate {
                    Text(date, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Author — dimmed, IAM leaf name only
            if let user = entry.lastModifiedUser, !user.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(user.components(separatedBy: "/").last ?? user)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            // Description — regular weight, readable
            if let desc = entry.description, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
            }

            // Value — code-block style with reveal toggle for SecureString
            if let value = entry.value {
                let isSecure = entry.type == .secureString
                HStack(alignment: .top, spacing: 6) {
                    Text(isSecure && !isRevealed ? "••••••••" : value)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(isRevealed ? nil : 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isSecure {
                        Button {
                            isRevealed.toggle()
                        } label: {
                            Image(systemName: isRevealed ? "eye.slash" : "eye")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help(isRevealed ? "Hide value" : "Reveal value")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            }

            // Labels / aliases
            if let labels = entry.labels, !labels.isEmpty {
                HStack(spacing: 4) {
                    ForEach(labels, id: \.self) { label in
                        Text(label)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Tags tab

struct TagsTabView: View {
    let node: ConfigNode
    @EnvironmentObject var appState: AppState
    @State private var newKey: String = ""
    @State private var newValue: String = ""
    @State private var hoveredTagKey: String?
    @State private var editingTagKey: String?
    @State private var editingValue: String = ""
    @State private var tagPendingDeletion: String?

    private var tagsState: AppState.TagsState? {
        appState.tagsCache[node.fullPath]
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = tagsState?.error {
                inspectorErrorView(error)
            } else if tagsState == nil || tagsState?.isLoading == true {
                ProgressView("Loading tags…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let tags = tagsState?.tags ?? []
                if tags.isEmpty {
                    Text("No tags")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(tags, id: \.key) { tag in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tag.key ?? "")
                                            .font(.caption.weight(.medium))
                                            .textSelection(.enabled)
                                        if editingTagKey == tag.key {
                                            TextField("Value", text: $editingValue)
                                                .font(.caption)
                                                .textFieldStyle(.plain)
                                                .onSubmit { commitEdit(key: tag.key!) }
                                                .onAppear { editingValue = tag.value ?? "" }
                                        } else {
                                            Text(tag.value ?? "")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .textSelection(.enabled)
                                                .onTapGesture(count: 2) {
                                                    editingTagKey = tag.key
                                                    editingValue = tag.value ?? ""
                                                }
                                        }
                                    }
                                    Spacer()
                                    Button {
                                        if let key = tag.key {
                                            tagPendingDeletion = key
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.tertiary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove tag")
                                    .opacity(hoveredTagKey == tag.key ? 1 : 0.3)
                                    .animation(.easeInOut(duration: 0.15), value: hoveredTagKey)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                                .onHover { isHovering in
                                    hoveredTagKey = isHovering ? tag.key : nil
                                }
                                .contextMenu {
                                    if let key = tag.key {
                                        Button("Remove Tag", role: .destructive) {
                                            tagPendingDeletion = key
                                        }
                                    }
                                }
                                Divider()
                            }
                        }
                    }
                }

                Divider()

                // Add tag row
                HStack(spacing: 6) {
                    TextField("Key", text: $newKey)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    TextField("Value", text: $newValue)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .onSubmit { submitTag() }
                    Button {
                        submitTag()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(newKey.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(10)
            }
        }
        .onAppear {
            Task { await appState.loadTags(for: node.fullPath) }
        }
        .onChange(of: node.id) { _, _ in
            newKey = ""
            newValue = ""
            editingTagKey = nil
            tagPendingDeletion = nil
            Task { await appState.loadTags(for: node.fullPath) }
        }
        .alert(
            "Remove Tag",
            isPresented: Binding(
                get: { tagPendingDeletion != nil },
                set: { if !$0 { tagPendingDeletion = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { tagPendingDeletion = nil }
            Button("Remove", role: .destructive) {
                if let key = tagPendingDeletion {
                    Task { await appState.removeTag(from: node.fullPath, key: key) }
                }
                tagPendingDeletion = nil
            }
        } message: {
            if let key = tagPendingDeletion {
                Text("Are you sure you want to remove the tag \"\(key)\"?")
            }
        }
    }

    private func submitTag() {
        let key = newKey.trimmingCharacters(in: .whitespaces)
        let val = newValue.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        Task { await appState.addTag(to: node.fullPath, key: key, value: val) }
        newKey = ""
        newValue = ""
    }

    private func commitEdit(key: String) {
        let value = editingValue.trimmingCharacters(in: .whitespaces)
        editingTagKey = nil
        Task { await appState.updateTag(on: node.fullPath, key: key, value: value) }
    }
}

// MARK: - Shared error view

private func inspectorErrorView(_ message: String) -> some View {
    VStack(spacing: 10) {
        Image(systemName: "lock.shield")
            .font(.title2)
            .foregroundStyle(.secondary)
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
