# Sidebar Add Button Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the "Add Parameter" entry point out of the toolbar cluster into (1) a bordered footer button inside the sidebar and (2) a hover-revealed "+" on each folder row, and refactor the Add sheet so folder context appears as a breadcrumb header instead of an inline prefix.

**Architecture:** The sidebar gains two new UI elements and one new closure prop (`onAdd: (String?) -> Void`). ContentView owns a new `pendingAddParentPath` state that the hover "+" sets; the footer passes `nil` and falls back to the existing `newValuePathPrefix` derivation. The Add sheet's `onAdd` closure signature changes from `(name, …)` to `(fullPath, …)` so the path is computed exactly once — inside the sheet's `submit()` — and both the duplicate check and the AppState call agree on the final path.

**Tech Stack:** SwiftUI, macOS 14+, single Xcode target. No unit-test harness in this project — each task verifies via `xcodebuild` build and one concrete UI behaviour to click.

**Reference spec:** [docs/superpowers/specs/2026-04-22-sidebar-add-button-design.md](docs/superpowers/specs/2026-04-22-sidebar-add-button-design.md)

**Build verification command used throughout:**
```bash
xcodebuild -scheme AWSSSMParamStoreUI -destination 'platform=macOS' build 2>&1 \
  | grep -E "(error:|warning:|Build succeeded|Build FAILED)"
```
Expected after every task: `Build succeeded` with no new warnings.

---

### Task 1: Thread `onAdd` closure through SidebarView → NodeTreeView → FolderRow

Adds the plumbing so later tasks can invoke Add from two places. No visible behavior change yet — both callsites pass a no-op closure, so the app still looks identical.

**Files:**
- Modify: `AWSSSMParamStoreUI/Views/SidebarView.swift`
- Modify: `AWSSSMParamStoreUI/ContentView.swift` (one callsite update)

- [ ] **Step 1: Add `onAdd` prop to `SidebarView`**

Edit `AWSSSMParamStoreUI/Views/SidebarView.swift`. Add a new stored property to `SidebarView` right after `var onEnterDetail: () -> Void = {}` (around line 7):

```swift
var onEnterDetail: () -> Void = {}
var onAdd: (String?) -> Void = { _ in }
```

The default `{ _ in }` keeps existing call-sites compiling without changes.

- [ ] **Step 2: Add `onAdd` prop to `NodeTreeView`**

In the same file, modify `NodeTreeView` (around line 120). Add a new stored property:

```swift
struct NodeTreeView: View {
    let node: ConfigNode
    @Binding var selection: String?
    @Binding var expandedFolders: Set<String>
    let onAddUnderFolder: (String) -> Void
    @EnvironmentObject var appState: AppState
    @State private var showDeleteConfirmation = false
```

Then update the recursive instantiation inside `NodeTreeView.body` (inside `DisclosureGroup`'s children ForEach, around line 158):

```swift
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
```

- [ ] **Step 3: Pass `onAddUnderFolder` from `SidebarView` to its two `NodeTreeView` callsites**

Inside `SidebarView.body`, there are two `ForEach(rootFolders) { node in NodeTreeView(...) }` and `ForEach(rootLeaves) { node in NodeTreeView(...) }` (around lines 27-35). Update both to pass `onAddUnderFolder`:

```swift
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
```

- [ ] **Step 4: Add `onAdd` callback param to `FolderRow`**

In the same file, modify `FolderRow` (around line 289). Add a new prop:

```swift
struct FolderRow: View {
    let node: ConfigNode
    let onAdd: () -> Void
    let onDelete: () -> Void
```

- [ ] **Step 5: Pass `onAdd` into `FolderRow` from `NodeTreeView`**

In `NodeTreeView.body`, the `DisclosureGroup` label currently calls `FolderRow(node: node, onDelete: …)` (around line 162). Update it to pass the partial-applied callback:

```swift
} label: {
    FolderRow(
        node: node,
        onAdd: { onAddUnderFolder(node.fullPath) },
        onDelete: { showDeleteConfirmation = true }
    )
    .tag(node.id)
}
```

- [ ] **Step 6: Build**

Run the build verification command. Expected: `Build succeeded`.

If it fails, read the error message and fix. Common issue: `FolderRow` being called somewhere else without `onAdd` — check the full file for any other callers.

- [ ] **Step 7: Commit**

```bash
git add AWSSSMParamStoreUI/Views/SidebarView.swift
git commit -m "Thread onAdd closure through sidebar view hierarchy"
```

---

### Task 2: Add the sidebar footer button

Adds the full-width bordered "+ Add Parameter" button pinned at the bottom of the sidebar. Clicking it calls `onAdd(nil)`, which is currently a no-op — wiring comes in Task 4.

**Files:**
- Modify: `AWSSSMParamStoreUI/Views/SidebarView.swift`

- [ ] **Step 1: Add the `AddParameterFooterButton` view**

At the end of `AWSSSMParamStoreUI/Views/SidebarView.swift` (after the closing `}` of `FolderRow`), add:

```swift
// MARK: - Add Parameter Footer Button

private struct AddParameterFooterButton: View {
    let isDisabled: Bool
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
        .disabled(isDisabled)
        .help(isDisabled ? (disabledReason ?? "Unavailable") : "Add Parameter (⇧⌘N)")
        .padding(10)
    }
}
```

Note: we deliberately do NOT add `.keyboardShortcut(...)` on this button. The ⇧⌘N shortcut is owned by the hidden binding in Task 5 so it works even when the sidebar is hidden/collapsed.

- [ ] **Step 2: Restructure `SidebarView.body` to include the footer**

The current `SidebarView.body` is a single `Group { … }` with modifiers. Wrap it in a `VStack(spacing: 0)` with the footer underneath. Replace the body (currently lines 11–74) with:

```swift
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
            isDisabled: appState.currentConnection == nil || appState.isConnecting,
            disabledReason: {
                if appState.isConnecting { return "Connecting…" }
                if appState.currentConnection == nil { return "Connect to a source to add parameters" }
                return nil
            }(),
            onTap: { onAdd(nil) }
        )
    }
    .onChange(of: selection) { _, newSelection in
        if let selectedId = newSelection {
            expandParents(for: selectedId)
        }
    }
    .onAppear {
        if let selectedId = selection {
            expandParents(for: selectedId)
        }
    }
}
```

- [ ] **Step 3: Build**

Run the build verification command. Expected: `Build succeeded`.

- [ ] **Step 4: Manual smoke**

Open the app. Confirm the sidebar now has a bordered "+ Add Parameter" button at the bottom. Clicking it should do nothing yet (no-op wiring). It should be disabled when no connection is active.

- [ ] **Step 5: Commit**

```bash
git add AWSSSMParamStoreUI/Views/SidebarView.swift
git commit -m "Add sidebar footer button for New Parameter"
```

---

### Task 3: Add hover "+" on folder rows

Folder rows gain a hover state. On hover, the count badge is replaced by a soft-tinted accent "+" button. Cursor-on-"+" gets a gentle filled background (mockup variant 1). Leaves are unaffected.

**Files:**
- Modify: `AWSSSMParamStoreUI/Views/SidebarView.swift`

- [ ] **Step 1: Add `HoverTintButtonStyle`**

At the end of `AWSSSMParamStoreUI/Views/SidebarView.swift`, add:

```swift
// MARK: - Hover Tint Button Style

private struct HoverTintButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverTintBody(configuration: configuration)
    }

    private struct HoverTintBody: View {
        let configuration: ButtonStyle.Configuration
        @State private var isHot: Bool = false

        var body: some View {
            configuration.label
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHot ? Color.accentColor.opacity(0.18) : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 5))
                .onHover { isHot = $0 }
                .opacity(configuration.isPressed ? 0.6 : 1)
        }
    }
}
```

- [ ] **Step 2: Add hover state to `FolderRow`**

In `FolderRow` (around line 289), add a `@State` property and an `.onHover` modifier. The current `FolderRow` body ends with `.contentShape(Rectangle()).contextMenu { … }` — add the hover-state plumbing and swap the trailing count badge for a conditional:

```swift
struct FolderRow: View {
    let node: ConfigNode
    let onAdd: () -> Void
    let onDelete: () -> Void
    @State private var isHovered: Bool = false

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
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(HoverTintButtonStyle())
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
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
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
```

- [ ] **Step 3: Build**

Run the build verification command. Expected: `Build succeeded`.

- [ ] **Step 4: Manual smoke**

Open the app, connect to a source, expand a folder tree. Hover over a folder row — the count badge should fade out and a "+" should fade in. Move the cursor directly onto the "+" — a faint blue fill appears behind it. Move the cursor to a leaf — no "+" appears. Clicking "+" does nothing yet (wiring comes in Task 4).

- [ ] **Step 5: Commit**

```bash
git add AWSSSMParamStoreUI/Views/SidebarView.swift
git commit -m "Add hover + button on folder rows"
```

---

### Task 4: Wire the Add closure in ContentView

Adds `pendingAddParentPath` state, passes `onAdd` closure into `SidebarView`, computes the effective `pathPrefix` for the overlay (hover-path wins over selection), and resets the pending path when the sheet dismisses.

**Files:**
- Modify: `AWSSSMParamStoreUI/ContentView.swift`

- [ ] **Step 1: Add `pendingAddParentPath` state**

In `ContentView`, find the block of `@State` declarations near the top (around line 13-19). Add:

```swift
@State private var pendingAddParentPath: String? = nil
```

next to `@State private var showingAddSheet = false`.

- [ ] **Step 2: Add an `effectivePathPrefix` computed property**

Just after `newValuePathPrefix` (ends around line 49), add:

```swift
private var effectivePathPrefix: String {
    if let explicit = pendingAddParentPath {
        return explicit.hasSuffix("/") ? explicit : explicit + "/"
    }
    return newValuePathPrefix
}
```

- [ ] **Step 3: Pass `onAdd` into `SidebarView`**

Find the `SidebarView(...)` call inside `ContentView.body` (around line 76). Add the `onAdd:` parameter between `focusRequest` and `onEnterDetail`:

```swift
SidebarView(
    selection: $selection,
    focusRequest: $sidebarFocusRequest,
    onEnterDetail: { detailFocusRequest = true },
    onAdd: { parentPath in
        pendingAddParentPath = parentPath
        showingAddSheet = true
    }
)
.environmentObject(appState)
.navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
```

- [ ] **Step 4: Use `effectivePathPrefix` in the overlay**

Find the `AddParameterOverlay(...)` call (around line 170). Change `pathPrefix: newValuePathPrefix` to `pathPrefix: effectivePathPrefix`:

```swift
AddParameterOverlay(
    isPresented: $showingAddSheet,
    pathPrefix: effectivePathPrefix,
    pathExists: { path in
        let strippedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return findNode(id: path, nodes: appState.rootNodes) != nil
            || findNode(id: strippedPath, nodes: appState.rootNodes) != nil
    },
    onAdd: { name, value, type, description in
        Task {
            let sanitized = String(name.drop(while: { $0 == "/" }))
            let path = effectivePathPrefix + sanitized
            let added = await appState.addParameter(path: path, value: value, type: type, description: description)
            if added {
                selection = path
                detailFocusRequest = true
            }
        }
    }
)
.transition(.opacity)
```

Note the two changes in that closure: `pathPrefix: effectivePathPrefix`, and the new `sanitized` line inside `onAdd:`. The `newValuePathPrefix + name` becomes `effectivePathPrefix + sanitized`.

- [ ] **Step 5: Reset `pendingAddParentPath` on sheet dismiss**

After the `.animation(.easeInOut(duration: 0.15), value: showingAddSheet)` line (around line 192), add:

```swift
.onChange(of: showingAddSheet) { _, isShowing in
    if !isShowing { pendingAddParentPath = nil }
}
```

- [ ] **Step 6: Build**

Run the build verification command. Expected: `Build succeeded`.

- [ ] **Step 7: Manual smoke**

Open the app. Click the sidebar footer "+ Add Parameter" with no selection → sheet opens, the prefix text inside the sheet still shows `/`. Select a folder `/app/db` and click the footer "+" → sheet opens with prefix `/app/db/`. Hover a different folder `/infra` and click its "+" → sheet opens with prefix `/infra/` (ignoring the selected folder). Close the sheet; click the footer "+" again with `/app/db` still selected → sheet opens with `/app/db/` prefix (pending-path was cleared on dismiss).

Important: the existing sheet still shows the prefix inline — the breadcrumb-based UI comes in Task 6. Here we only verify wiring is correct.

- [ ] **Step 8: Commit**

```bash
git add AWSSSMParamStoreUI/ContentView.swift
git commit -m "Wire sidebar Add closure to Add sheet prefix"
```

---

### Task 5: Remove toolbar Add button and restore ⇧⌘N via hidden shortcut

Deletes the Add button from the `.principal` ToolbarItemGroup. Adds an invisible `Button` with the ⇧⌘N shortcut inside a `.background { ZStack { … } }` at the end of the main body (mirrors the pattern in `DetailView`).

**Files:**
- Modify: `AWSSSMParamStoreUI/ContentView.swift`

- [ ] **Step 1: Delete the toolbar Add button block**

In `ContentView.swift`, find the `.principal` `ToolbarItemGroup` (around line 248). Delete the entire Add button block (lines 249-258):

```swift
                // Add button
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .help("Add new parameter (⇧⌘N)")
                .disabled(appState.currentConnection == nil)
```

After deletion, the `.principal` group should start with `// Connection selector dropdown` followed by the Menu that was the second item.

- [ ] **Step 2: Add the hidden ⇧⌘N button**

Find the main body's modifier chain in `ContentView.body`. The order is: `NavigationSplitView { … }` → several `.overlay { … }.animation(...)` pairs → `.onChange(of: showingAddSheet)` (added in Task 4) → `.navigationTitle(…)` → `.navigationSubtitle(…)` → `.toolbar { … }`.

Add a new `.background { … }` modifier **immediately after** the Task-4 `.onChange(of: showingAddSheet) { … }` line and **before** `.navigationTitle(windowTitle)`:

```swift
.background {
    Button("") {
        pendingAddParentPath = nil
        showingAddSheet = true
    }
    .keyboardShortcut("n", modifiers: [.command, .shift])
    .opacity(0)
    .frame(width: 0, height: 0)
    .disabled(appState.currentConnection == nil)
}
```

The `pendingAddParentPath = nil` line ensures the shortcut always falls back to selection-derived prefix rather than leaking state from a previous hover-"+" click.

- [ ] **Step 3: Build**

Run the build verification command. Expected: `Build succeeded`.

- [ ] **Step 4: Manual smoke**

Open the app. Toolbar should no longer show the "Add" button in the principal cluster — Connection, Region, Refresh, Shortcuts remain. Press ⇧⌘N — the Add sheet opens. With no connection, ⇧⌘N should do nothing (shortcut disabled).

- [ ] **Step 5: Commit**

```bash
git add AWSSSMParamStoreUI/ContentView.swift
git commit -m "Remove toolbar Add button, keep shortcut via hidden binding"
```

---

### Task 6: Refactor Add sheet to use a breadcrumb header and sanitized submit

Replaces the inline prefix-next-to-name-field layout with a breadcrumb row above the form (`Adding under /app/db`). Renames the field label from "Path" to "Name". Makes `submit()` strip leading slashes from the name so `/foo` doesn't produce `{prefix}//foo`.

**Files:**
- Modify: `AWSSSMParamStoreUI/ContentView.swift`

- [ ] **Step 1: Add a `breadcrumbText` computed property inside `AddParameterOverlay`**

In `AddParameterOverlay` (around line 692), next to the other private computed properties, add:

```swift
private var breadcrumbText: String {
    if pathPrefix == "/" { return "root" }
    return pathPrefix.hasSuffix("/") ? String(pathPrefix.dropLast()) : pathPrefix
}
```

- [ ] **Step 2: Update `submit()` to sanitize leading slashes**

Find `submit()` (around line 719). Replace the body:

```swift
private func submit() {
    guard isValid else { return }
    let trimmed = parameterName.trimmingCharacters(in: .whitespaces)
    let sanitized = String(trimmed.drop(while: { $0 == "/" }))
    let fullPath = pathPrefix + sanitized
    if pathExists(fullPath) {
        withAnimation(.easeInOut(duration: 0.15)) { showsDuplicateError = true }
        return
    }
    onAdd(sanitized, parameterValue, parameterType, parameterDescription.isEmpty ? nil : parameterDescription)
    dismiss()
}
```

Key changes: compute `sanitized`, use it in both `fullPath` and the `onAdd` callback's first argument. The Task-4 change in `ContentView.onAdd` already re-applies the same sanitize-and-concatenate logic, so even if the name arrives unsanitized (e.g. from a future path that bypasses this), the result is still correct. This duplication is intentional defense.

- [ ] **Step 3: Insert the breadcrumb row**

Find the title row inside `AddParameterOverlay.body` (around line 738-747):

```swift
// ── Title ────────────────────────────────────────────────────
HStack {
    Text("New Parameter")
        .font(.title2.weight(.semibold))
    Spacer()
}
.padding(.horizontal, 48)
.padding(.top, 60)
.padding(.bottom, 4)
```

Immediately after this block (before `// ── Fields area`), insert:

```swift
// ── Breadcrumb ───────────────────────────────────────────────
HStack(spacing: 6) {
    Text("Adding under")
        .font(.caption)
        .foregroundStyle(.secondary)
    Text(breadcrumbText)
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .truncationMode(.head)
    Spacer()
}
.padding(.horizontal, 48)
.padding(.bottom, 16)
```

- [ ] **Step 4: Rename the Path field group and remove the inline prefix**

Find the `// Path` field group (around line 752-789). Replace the entire `fieldGroup(label: "Path") { … }` block with:

```swift
// Name
fieldGroup(label: "Name") {
    TextField("parameter name", text: $parameterName)
        .font(.system(.body, design: .monospaced))
        .textFieldStyle(.plain)
        .focused($isNameFocused)
        .onSubmit { submit() }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    showsDuplicateError
                        ? AnyShapeStyle(Color.red.opacity(0.8))
                        : AnyShapeStyle(.separator),
                    lineWidth: showsDuplicateError ? 1.5 : 0.5
                )
        )

    if showsDuplicateError {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
            Text("A parameter at this path already exists.")
                .font(.caption)
        }
        .foregroundStyle(.red)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
```

Key differences vs. the original block:
- Label `"Path"` → `"Name"`.
- The `HStack(spacing: 0) { Text(pathPrefix)…; TextField("…enter path", …) }` is gone; the `TextField` stands alone with a `"parameter name"` placeholder.
- The `TextField` now carries the field's own padding, background, and stroke (previously those lived on the outer `HStack`).

- [ ] **Step 5: Build**

Run the build verification command. Expected: `Build succeeded`.

- [ ] **Step 6: Manual smoke — breadcrumb + prefill**

Open the app, connect to a source.

- Click footer "+" with no selection → sheet opens; breadcrumb reads `Adding under root`; name field placeholder is `parameter name`.
- Click footer "+" with folder `/app/db` selected → breadcrumb reads `Adding under /app/db`.
- Click hover "+" on folder `/infra` → breadcrumb reads `Adding under /infra`.
- Press ⇧⌘N with no selection → breadcrumb reads `Adding under root`.

- [ ] **Step 7: Manual smoke — leading-slash sanitization**

With any folder selected (e.g. `/app/db`), open the Add sheet.

- Type name `foo`, add a value, submit → parameter at `/app/db/foo` is created.
- Type name `/bar`, value, submit → parameter at `/app/db/bar` (leading slash stripped — no `//`).
- Type name `///baz`, value, submit → parameter at `/app/db/baz`.
- Type name `nested/child`, value, submit → parameter at `/app/db/nested/child` (internal slashes preserved — this creates nested structure).

Verify by looking at the sidebar after each add: the newly-added node should appear under the correct parent with no leading-slash weirdness.

- [ ] **Step 8: Manual smoke — duplicate error**

Select any existing parameter's parent folder, open the Add sheet, type the existing param's name, try to submit. Expected: the name field border turns red, `"A parameter at this path already exists."` shows below, submit is blocked.

- [ ] **Step 9: Commit**

```bash
git add AWSSSMParamStoreUI/ContentView.swift
git commit -m "Refactor Add sheet: breadcrumb header, sanitize leading slashes"
```

---

### Task 7: Final verification pass

Exercise every path once, confirm nothing from earlier tasks regressed.

- [ ] **Step 1: Full build**

Run the build verification command one more time. Expected: `Build succeeded` with no warnings.

- [ ] **Step 2: Walk the full UX**

Launch the app fresh and walk through:

1. Connect to a source.
2. Toolbar shows Connection/Region/Refresh/Shortcuts — no Add button.
3. Sidebar footer: bordered "+ Add Parameter" visible and enabled.
4. Click footer "+" with nothing selected → sheet opens, breadcrumb shows `Adding under root`. Dismiss.
5. Click a folder, then footer "+" → sheet opens, breadcrumb shows that folder's path. Dismiss.
6. Hover a different folder, click the hover "+" → sheet opens, breadcrumb shows the hovered folder's path. Dismiss.
7. Dismiss without adding; click footer "+" again → breadcrumb returns to the selected-folder path.
8. ⇧⌘N shortcut opens the sheet; breadcrumb reflects the selection.
9. Disconnect (or launch with no connection): footer button is disabled with tooltip; ⇧⌘N is disabled; no folders exist so hover "+" is moot.
10. Add a parameter with a plain name, a slash-prefixed name, and a nested name — all land at the correct path.
11. Try to add a duplicate — red border + error message appear.
12. Hover a leaf row — no "+" appears (only count/type badge).
13. Hover a folder row — count badge replaced by "+"; cursor on "+" shows faint blue tint.
14. Inspector panel (⌥⌘I) still opens/closes. Tag add/edit/remove still works.

- [ ] **Step 3: Tag this task complete**

No commit needed — all task-level commits already landed. Summarize to the user: "Sidebar Add button redesign complete. Footer + hover "+" wired, toolbar Add removed, Add sheet refactored to breadcrumb layout with leading-slash sanitization."
