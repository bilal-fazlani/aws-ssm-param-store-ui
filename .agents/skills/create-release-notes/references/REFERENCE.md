# Release Notes Reference

## How release notes are used

The release workflow at `.github/workflows/release.yml` looks for a file at `release_notes/v$VERSION.md` during the "Prepare release notes" step. If found, it becomes the body of the GitHub Release. GitHub's `generate_release_notes: true` flag appends auto-generated contributor/PR info after it.

The "What's New" overlay in the app fetches the release body from the GitHub Releases API and renders it with Textual's `StructuredText(markdown:)`. This means the release notes must be valid markdown that reads well in both GitHub's web UI and inside the app's glass overlay.

## File naming

- Directory: `release_notes/`
- File name: `v{VERSION}.md` (e.g. `v1.7.md`, `v2.0.md`)

## Content guidelines

- **Title**: `# v{VERSION}` as the first line.
- **Summary**: One or two sentences describing the release at a high level.
- **What's New section**: Group related changes under descriptive headings (e.g. `**Feature Name**`). Use bullet points for individual changes. Write from the user's perspective — what they can do now, not what code changed.
- **Changelog link**: Always include a `**Full Changelog**` link at the bottom pointing to the GitHub compare URL between the previous and new tags.

## Version tags

All tags follow the pattern `v{MAJOR}.{MINOR}` (e.g. `v1.6`). There are no patch versions currently — the project uses `MAJOR.MINOR` only.

## Example: v1.0 release notes

The v1.0 release notes are a good reference for tone and structure:

- Title is `# v1.0.0`
- Summary paragraph describes what the app is
- Features grouped under bold headings: **Connection Management**, **Parameter Browser**, **Search**, etc.
- Each feature has 2-5 bullet points describing capabilities
- Ends with a **Requirements** section

For subsequent releases (v1.1+), the structure should be simpler — just What's New changes, not a full feature catalogue.
