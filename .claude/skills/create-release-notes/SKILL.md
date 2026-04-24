---
name: create-release-notes
description: Use when the user asks to create release notes, write a changelog, prepare a release, or draft what's-new content for AWSSSMParamStoreUI. Generates a release_notes/v{VERSION}.md file by diffing git history between tags.
---

# Create Release Notes

Generate a `release_notes/v{VERSION}.md` file by analyzing the git diff and commit history between two versions.

## Inputs

Gather these from the user (use AskUserQuestion tool when available):

| Input | Required | Default |
|-------|----------|---------|
| Latest ref | No | `HEAD` |
| Version upgrade | No | Minor bump from latest tag (e.g. `1.6` → `1.7`) |

### Version resolution

- If the user says **"minor"** or gives no version: bump the minor component of the latest tag (e.g. `1.6` → `1.7`).
- If the user says **"major"**: bump the major component and reset minor to 0 (e.g. `1.6` → `2.0`).
- If the user gives an **exact version** (e.g. `1.8` or `2.1`): use it as-is.

### Previous version resolution

The previous version to diff against is **always the latest existing tag** (the most recent `v*` tag by version order), regardless of whether the new release is a major or minor bump.

Rationale: the release notes file describes *what changed in this release*, not a cumulative history. Users upgrading across multiple versions see each release's notes in sequence via the in-app What's New catch-up flow, so a cumulative major-release doc would double-count changes they've already seen. If you want a cumulative "v1 → v2 highlights" artifact, make it a separate section inside the release notes file (or a separate file), not the default body.

To find the previous tag:
```bash
git tag --list 'v*' --sort=-v:refname | head -1
```

## Workflow

1. **Resolve the new version** from user input (see rules above).

2. **Resolve the previous version** — always the latest existing tag.

3. **Gather the diff** between the previous tag and the latest ref:
   ```bash
   git log v{PREVIOUS}..{LATEST_REF} --oneline
   git diff v{PREVIOUS}..{LATEST_REF} --stat
   ```

4. **Read the template** at `assets/template.md` (relative to this skill).

5. **Analyze the changes** — read relevant source files if commit messages are unclear. Categorize changes from the user's perspective: new features, improvements, bug fixes.

6. **Draft the release notes** using the template structure. For detailed formatting guidance, see [references/REFERENCE.md](references/REFERENCE.md).

7. **Write the file** to `release_notes/v{NEW_VERSION}.md`.

8. **Show the user** the generated content for review.

9. **Create the git tag** locally:
   ```bash
   git tag v{NEW_VERSION}
   ```

10. **Ask the user** whether to push the commits and tag to remote. If they confirm, run:
    ```bash
    git push && git push origin v{NEW_VERSION}
    ```

## Writing style

- Write from the user's perspective — describe what they can now do, not what code changed.
- Use bullet points under bold feature headings.
- Keep descriptions concise — one line per change when possible.
- Do not mention internal implementation details, file names, or function names.
