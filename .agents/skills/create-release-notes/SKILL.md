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
| Previous version tag | Yes | — |
| Latest ref | No | `HEAD` |
| Version upgrade | No | Minor bump from previous (e.g. `1.6` → `1.7`) |

### Version resolution

- If the user says **"minor"** or gives no version: bump the minor component of the previous version (e.g. `1.6` → `1.7`).
- If the user says **"major"**: bump the major component and reset minor to 0 (e.g. `1.6` → `2.0`).
- If the user gives an **exact version** (e.g. `1.8` or `2.1`): use it as-is.

## Workflow

1. **Resolve the new version** from user input (see rules above).

2. **Gather the diff** between the previous tag and the latest ref:
   ```bash
   git log v{PREVIOUS}..{LATEST_REF} --oneline
   git diff v{PREVIOUS}..{LATEST_REF} --stat
   ```

3. **Read the template** at `assets/template.md` (relative to this skill).

4. **Analyze the changes** — read relevant source files if commit messages are unclear. Categorize changes from the user's perspective: new features, improvements, bug fixes.

5. **Draft the release notes** using the template structure. For detailed formatting guidance, see [references/REFERENCE.md](references/REFERENCE.md).

6. **Write the file** to `release_notes/v{NEW_VERSION}.md`.

7. **Show the user** the generated content for review.

## Writing style

- Write from the user's perspective — describe what they can now do, not what code changed.
- Use bullet points under bold feature headings.
- Keep descriptions concise — one line per change when possible.
- Do not mention internal implementation details, file names, or function names.
