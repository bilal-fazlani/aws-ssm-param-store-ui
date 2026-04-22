# Sidebar Add Button Redesign

Date: 2026-04-22

## Context

The Add Parameter button currently lives in the toolbar's `.principal` group, mixed with Connection, Region, Refresh, and Shortcuts. SwiftUI merges `ToolbarItemGroup`s of the same placement into one visual cluster, so the Add button cannot be visually separated from the rest without moving to a different placement slot entirely.

The user wants Add to feel like a first-class action on the parameter tree, and to stop competing with connection/region controls for attention. This design moves Add into the sidebar itself — the container it actually operates on — using two complementary entry points that together follow native macOS patterns (Mail, Notes, Finder sidebar).

## Goals

- Remove the Add button from the toolbar cluster.
- Give the sidebar a single, always-visible, prominent home for Add (bordered footer button).
- Give folder rows a contextual, hover-revealed shortcut for "add a child under this folder".
- Keep the ⇧⌘N keyboard shortcut working.
- Improve the Add sheet's folder-context display so the user always knows where the parameter will land.

## Non-goals

- No empty-state CTA in the detail pane (the footer button covers first-run).
- No redesign of the Add sheet's fields beyond the path/name layout.
- No changes to keyboard navigation or selection semantics.
- No new validation beyond the leading-slash fix — trailing slashes and internal `//` remain out of scope.

## Approach

### Overview

Two new entry points in the sidebar; existing toolbar entry removed:

1. **Sidebar footer button** — full-width bordered `"+ Add Parameter"`, always visible under the tree. Prefills the Add sheet from the currently-selected node (same `newValuePathPrefix` logic used today).
2. **Hover "+" on folder rows** — replaces the count badge on hover; soft-tint background when the cursor is directly on it. Prefills the sheet from the hovered folder's path (ignoring selection).

The shared Add sheet is refactored so folder context appears as a breadcrumb header (`Adding under /app/db`) instead of an inline prefix beside the name field. The name field becomes a standalone `TextField` with a `parameter name` placeholder.

### Entry point 1: sidebar footer button

`SidebarView` ([AWSSSMParamStoreUI/Views/SidebarView.swift](AWSSSMParamStoreUI/Views/SidebarView.swift)) grows a footer:

```
VStack(spacing: 0) {
    <existing List / shimmer block>        // fills vertically
    Divider()
    AddParameterFooterButton(onTap: …)     // bordered button, padded
}
```

`AddParameterFooterButton` is a small local view — `Button(action:)` with an `HStack { Image(systemName: "plus"); Text("Add Parameter") }`, wrapped in `.buttonStyle(.bordered)` and `.padding(10)`.

- **Disabled state**: mirrors the old toolbar button — `.disabled(appState.currentConnection == nil || appState.isConnecting)`.
- **Tooltip**: `"Add Parameter (⇧⌘N)"` when enabled; `"Connect to a source to add parameters"` when disabled due to no connection; `"Connecting…"` while connecting.
- **Action**: invokes a new `onAdd: (String?) -> Void` closure on `SidebarView.init` with `nil` (footer = use selection-derived prefix).

### Entry point 2: hover "+" on folder rows

`FolderRow` ([AWSSSMParamStoreUI/Views/SidebarView.swift:289](AWSSSMParamStoreUI/Views/SidebarView.swift:289)) gains:

- `@State private var isHovered: Bool = false` + `.onHover { isHovered = $0 }` on the content shape.
- A new prop `let onAdd: () -> Void` (threaded through `NodeTreeView` alongside the existing `onDelete`).
- The trailing region becomes conditional:
  - When not hovered → existing count badge.
  - When hovered → `Button(action: onAdd) { Image(systemName: "plus") … }` styled with a new `HoverTintButtonStyle` (variant 1 from the mockups: faint `Color.accentColor.opacity(0.18)` rounded-rect behind the label when the cursor is directly on the button).
- Transition: `.animation(.easeInOut(duration: 0.12), value: isHovered)` on the swap.
- Tooltip: `"Add parameter under \(node.fullPath)"`.

`ParameterRow` (leaves) gets no hover "+" — leaves cannot have children.

`NodeTreeView` invokes `onAdd` with the folder's full path, which flows up to `SidebarView`'s `onAdd: (String?) -> Void` closure with a non-nil value.

### Wiring: two prefill sources

`ContentView` owns the Add sheet and gains a single new piece of state:

```swift
@State private var pendingAddParentPath: String? = nil
```

`SidebarView` is initialised with:

```swift
SidebarView(
    selection: $selection,
    focusRequest: $focusRequest,
    onAdd: { parentPath in
        pendingAddParentPath = parentPath   // nil from footer, folder path from hover "+"
        showingAddSheet = true
    },
    onEnterDetail: …
)
```

The sheet's `pathPrefix` becomes:

```swift
let pathPrefix: String = {
    if let explicit = pendingAddParentPath {
        return explicit.hasSuffix("/") ? explicit : explicit + "/"
    }
    return newValuePathPrefix   // selection-derived, unchanged
}()
```

On sheet dismiss, reset `pendingAddParentPath = nil`.

### Add sheet refactor (breadcrumb)

Modify `AddParameterOverlay` ([AWSSSMParamStoreUI/ContentView.swift:692](AWSSSMParamStoreUI/ContentView.swift:692)):

- Add a breadcrumb row above the fields area:
  ```swift
  HStack(spacing: 6) {
      Text("Adding under")
          .font(.caption)
          .foregroundStyle(.secondary)
      Text(breadcrumbText)
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(.primary)
          .lineLimit(1)
          .truncationMode(.head)
  }
  ```
- `breadcrumbText`:
  - If `pathPrefix == "/"` → `"root"`.
  - Else → `pathPrefix` with trailing `/` stripped.
- Rename the first field group's label from `"Path"` to `"Name"`.
- Replace the HStack-with-prefix layout at [ContentView.swift:754-765](AWSSSMParamStoreUI/ContentView.swift:754) with a plain `TextField("parameter name", text: $parameterName)`.
- Update `submit()` to sanitize leading slashes on the name before concatenation:
  ```swift
  let trimmed = parameterName.trimmingCharacters(in: .whitespaces)
  let sanitized = String(trimmed.drop(while: { $0 == "/" }))
  let fullPath = pathPrefix + sanitized
  ```
  This prevents `/foo` from becoming `//foo` (no visible trailing slash to cue the user after the refactor). Internal slashes are preserved so intentional nesting (`foo/bar`) still works.
- Duplicate-path error state still attaches to the name field's border, unchanged.

### Toolbar cleanup & shortcut retention

[ContentView.swift:248-258](AWSSSMParamStoreUI/ContentView.swift:248) — delete the Add button block inside the `.principal` `ToolbarItemGroup`. The principal cluster then holds only Connection, Region, Refresh, Shortcuts.

To keep ⇧⌘N working, add an invisible command button to the same hidden-shortcut stack that already holds the inspector toggle at [DetailView.swift:399-403](AWSSSMParamStoreUI/Views/DetailView.swift:399):

```swift
Button("") { showingAddSheet = true }
    .keyboardShortcut("n", modifiers: [.command, .shift])
    .opacity(0)
    .disabled(appState.currentConnection == nil)
```

## Files to modify

- [AWSSSMParamStoreUI/Views/SidebarView.swift](AWSSSMParamStoreUI/Views/SidebarView.swift) — add footer button, hover "+" on `FolderRow`, `HoverTintButtonStyle`, new `onAdd` closure prop.
- [AWSSSMParamStoreUI/ContentView.swift](AWSSSMParamStoreUI/ContentView.swift) — remove toolbar Add button; add hidden ⇧⌘N button; add `pendingAddParentPath` state; thread `onAdd` into `SidebarView`; wire prefill source into `AddParameterOverlay`; refactor the overlay's path field and add breadcrumb; sanitize leading slashes in `submit()`.

## Disabled states & edge cases

- **No connection** → footer button disabled; hidden ⇧⌘N button disabled; hover "+" never surfaces because the tree is empty.
- **Connecting** → same as no connection.
- **Empty tree, connected** → shimmer shows during load; footer button always mounted — no separate empty-state CTA needed.
- **Pending optimistic child** → unrelated to add; hover "+" still fires.
- **Deeply nested folders** → breadcrumb truncates from the head, matching today's inline prefix behavior.
- **Selection vs hover** — hover "+" always wins over selection; dismissing the sheet clears `pendingAddParentPath` so the next footer click falls back to the selection-derived prefix.
- **Concurrent duplicate** → existing `pathExists(fullPath)` check inside the sheet is unchanged.

## Verification

Manual, after implementation:

1. **Build clean**:
   ```bash
   xcodebuild -scheme AWSSSMParamStoreUI -destination 'platform=macOS' build 2>&1 \
     | grep -E "(error:|warning:|Build succeeded|Build FAILED)"
   ```
   Expect `Build succeeded`, no new warnings.

2. **Toolbar**: Add button no longer present in the principal cluster. Connection, Region, Refresh, Shortcuts still in place and in order.

3. **⇧⌘N** opens the Add sheet both with and without a selection. Disabled when no connection.

4. **Footer button**:
   - Full-width bordered `+ Add Parameter` at bottom of sidebar.
   - Disabled + tooltip when no connection.
   - With no selection → breadcrumb reads `Adding under root`.
   - With folder selected → breadcrumb shows that folder's path.
   - With leaf selected → breadcrumb shows the leaf's parent folder path.

5. **Hover "+"**:
   - Hovering any folder row swaps the count badge for a "+".
   - Direct cursor-on-"+" shows a faint accent-colored background (variant 1).
   - Leaves never show "+".
   - Clicking "+" opens the sheet with breadcrumb pinned to that folder, regardless of selection.
   - After dismissing, clicking footer "+" falls back to the selection-derived prefix.

6. **Sheet**:
   - Breadcrumb reads `Adding under <path>` or `Adding under root`.
   - Name field placeholder is `parameter name` (no leading slash).
   - Name `foo` → submits `{prefix}foo`.
   - Name `/foo` → submits `{prefix}foo` (leading slash stripped, no double slash).
   - Name `///foo` → same as above.
   - Name `foo/bar` → submits `{prefix}foo/bar` (internal slashes preserved).
   - Duplicate-path error still highlights the name field border.

7. **Optimistic flow**: adds still show pending spinner, then populate full metadata (the enrichment fix from earlier stays intact).

8. **Offline ⇧⌘N** → shortcut disabled, no sheet opens.
