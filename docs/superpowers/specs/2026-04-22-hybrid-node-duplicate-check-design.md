# Hybrid-Node Duplicate Check Fix

Date: 2026-04-22

## Context

The Add Parameter sheet's client-side duplicate check flags legitimate hybrid-node adds as duplicates. Concretely: when parameter `/a/b/c` exists, the tree has a synthetic folder node at `/a/b` (it exists only because `/a/b/c` shares that prefix — no actual AWS parameter sits at `/a/b`). If a user tries to add a parameter at `/a/b`, the Add sheet now shows "A parameter at this path already exists." and blocks submission.

This is incorrect. AWS SSM Parameter Store allows `/a/b` and `/a/b/c` to coexist as independent parameters, and this app explicitly models that dual behavior — see `ConfigNode.isValueNode` and the `FolderSummaryView` / hybrid detail pane. The check should only block when the target path actually has a value, not when it is merely a path prefix.

The check was introduced in commit `dd1a842` ("duplicate node check") and is a latent bug, not a regression from the recent sidebar-add-button work. It was easy to miss because the old toolbar Add button required typing the full path from scratch. The new hover "+" on folder rows makes the pattern trivial to trigger — click the "+" on the folder that represents the synthetic prefix, type a name that collides, submit.

## Goals

- Allow adding a value at a path where only a synthetic folder currently exists.
- Still block when the target path already holds a real value (leaf or hybrid).
- Still block when an optimistic add at the same path is in flight (no concurrent double-submits).
- Leave the error message and error-path styling unchanged — they stay accurate under the new semantics.

## Non-goals

- No change to AWS/SSM interaction. The duplicate check is client-side ergonomics; AWS would reject true duplicates server-side regardless.
- No change to any other validation (`isValid`, whitespace/slash sanitization, required value).
- No refactor of the `pathExists` closure signature.

## Approach

Use the predicate that already exists on `ConfigNode`: [`isValueNode`](AWSSSMParamStoreUI/Models/ConfigNode.swift:42). It returns `true` when the node has a `value`, a `serverValue`, or is mid-load (Phase-2 fetch not complete); it returns `false` for synthetic path-prefix-only folders.

Modify the `pathExists` closure in [`ContentView.swift`](AWSSSMParamStoreUI/ContentView.swift) to check the predicate instead of mere existence:

```swift
pathExists: { path in
    // Only an existing *value* blocks the add. A synthetic folder node (one that
    // exists only because deeper params use this as a path prefix) must still
    // allow hybrid adds — a path can legitimately be both a folder and a value.
    let strippedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
    let exactNode = findNode(id: path, nodes: appState.rootNodes)
    let strippedNode = findNode(id: strippedPath, nodes: appState.rootNodes)
    return (exactNode?.isValueNode ?? false) || (strippedNode?.isValueNode ?? false)
},
```

The `strippedPath` branch (defensive handling of IDs with a missing leading slash) is preserved. Both lookups now apply the same `isValueNode` filter.

Pending optimistic adds keep blocking automatically: `addParameter` at [`AppState.swift:346-355`](AWSSSMParamStoreUI/Models/AppState.swift:346) sets `value` and `serverValue` on the optimistic node, so `isValueNode` returns `true` for the duration of the in-flight AWS call. No extra code required.

## Files to modify

- [`AWSSSMParamStoreUI/ContentView.swift`](AWSSSMParamStoreUI/ContentView.swift) — four lines inside the `pathExists` closure passed to `AddParameterOverlay`.

## Behavior matrix

| State at target path | Old behavior | New behavior |
|---|---|---|
| Nothing exists | allow | allow |
| Leaf parameter exists | block | block |
| Only a synthetic folder exists (`/a/b/c` exists, adding `/a/b`) | **block (bug)** | **allow** |
| Hybrid node (path is both value and prefix of children) | block | block |
| Optimistic pending add in flight at that path | block | block |

## Verification

1. Build:
   ```bash
   xcodebuild -scheme AWSSSMParamStoreUI -destination 'platform=macOS' build 2>&1 \
     | grep -E "(error:|warning:|Build succeeded|Build FAILED)"
   ```
   Expected: `Build succeeded`, no new warnings.

2. Manual, in the running app against LocalStack or a real account:
   - Create a parameter at `/a/b/c` (so `/a/b` appears as a synthetic folder in the sidebar).
   - Hover `/a/b` in the sidebar → click the "+" → breadcrumb reads `Adding under /a/b`.
   - Type a name `foo`, a value, submit → parameter at `/a/b/foo` is created. (Control case — should have worked before too.)
   - Open Add sheet again from the root. Type `a/b` as the name → submit. Expected: parameter at `/a/b` is created (the hybrid case we're fixing). Sidebar now shows `/a/b` as both a folder (containing `c` and `foo`) and a value node.
   - Try adding `a/b` again → blocked with the existing red-border duplicate error (now it's a real duplicate).
   - Try adding a name that matches an existing leaf under `/a/b` (e.g. `c`) → blocked. Error stays accurate.
   - With any folder hovered, click "+" and submit an optimistic add; before it completes, try to add the same path again via ⇧⌘N → second attempt is blocked by the in-flight `isValueNode` check.
