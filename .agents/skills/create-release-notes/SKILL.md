---
name: create-release-notes
description: Generate release notes for a new version by diffing git history between tags. Use when the user asks to create release notes, write a changelog, prepare a release, or draft what's-new content.
---

# Create Release Notes

Generate a `release_notes/v{VERSION}.md` file by analyzing the git diff and commit history between two versions.

## Inputs

Gather these from the user (use AskQuestion tool when available):

| Input | Required | Default |
|-------|----------|---------|
| Latest ref | No | `HEAD` |
| Version upgrade | No | Minor bump from latest tag (e.g. `1.6` → `1.7`) |

### Version resolution

- If the user says **"minor"** or gives no version: bump the minor component of the latest tag (e.g. `1.6` → `1.7`).
- If the user says **"major"**: bump the major component and reset minor to 0 (e.g. `1.6` → `2.0`).
- If the user gives an **exact version** (e.g. `1.8` or `2.1`): use it as-is.

### Previous version resolution

The previous version to diff against depends on whether the new version is a **major** or **minor** release:

- **Minor release** (e.g. `1.7`, `2.1`, `2.3`): compare against the **latest tag** (the most recent `v*` tag by version order). This captures only the changes since the last release.
- **Major release** (e.g. `2.0`, `3.0`): compare against the **last major version tag** — the highest tag whose major component is less than the new major version (e.g. for `v2.0`, compare against `v1.0`; for `v3.0`, compare against `v2.0`). This captures all changes across the entire major cycle.

A version is considered a major release when its minor component is `0` — whether the user explicitly says "major", gives an exact version like `2.0` or `3`, or the resolved version has minor = 0.

To find the previous tag, list all tags and select the right one:
```bash
git tag --list 'v*' --sort=-v:refname
```

## Workflow

1. **Resolve the new version** from user input (see rules above).

2. **Resolve the previous version** to diff against (see rules above).

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

## Writing style

- Write from the user's perspective — describe what they can now do, not what code changed.
- Use bullet points under bold feature headings.
- Keep descriptions concise — one line per change when possible.
- Do not mention internal implementation details, file names, or function names.
