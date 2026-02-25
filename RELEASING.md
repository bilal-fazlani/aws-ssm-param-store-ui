# Releasing AWSSSMParamStoreUI

Releases are fully automated via GitHub Actions. Pushing a version tag triggers the workflow, which builds, signs, notarizes, publishes the GitHub release, and updates the Homebrew cask automatically.

---

## One-Time Setup

### 1. GitHub Actions Secrets

Add the following secrets to the **app repo** (`github.com/bilal-fazlani/aws-ssm-param-store-ui` → Settings → Secrets and variables → Actions):

| Secret | Value |
|---|---|
| `DEVELOPER_ID_CERT_P12` | Base64-encoded Developer ID Application `.p12` certificate |
| `DEVELOPER_ID_CERT_PASSWORD` | Password set when exporting the `.p12` |
| `NOTARIZATION_APPLE_ID` | Your Apple ID email |
| `NOTARIZATION_TEAM_ID` | Your 10-character Apple Team ID |
| `NOTARIZATION_PASSWORD` | App-specific password from [appleid.apple.com](https://appleid.apple.com) |
| `TAP_REPO_TOKEN` | GitHub PAT with `contents: write` on `bilal-fazlani/homebrew-tap` |

**Exporting the `.p12`:**
1. Open **Keychain Access → My Certificates**
2. Right-click **Developer ID Application: Bilal Fazlani** → Export
3. Save as `.p12` and set a password — that password is `DEVELOPER_ID_CERT_PASSWORD`
4. Base64-encode it: `base64 -i ~/Desktop/cert.p12 | pbcopy` — paste as `DEVELOPER_ID_CERT_P12`

---

## How to Release

### 1. Write release notes (optional)

Create `release_notes/v{version}.md` and commit it. If the file is absent the GitHub Release will have an empty body.

```bash
# Example
cat > release_notes/v1.1.md << 'EOF'
## What's new
- Added feature X
- Fixed bug Y
EOF
git add release_notes/v1.1.md
git commit -m "Add release notes for v1.1"
```

### 2. Push a version tag

```bash
git tag v1.1
git push origin v1.1
```

This triggers the workflow. You can monitor it under **Actions** in the GitHub UI.

---

## What the Workflow Does

1. Imports the Developer ID certificate into a temporary keychain
2. Archives the app with `xcodebuild archive`
3. Exports the `.app` with Developer ID signing via `ExportOptions.plist`
4. Packages the `.app` into a DMG
5. Signs the DMG with `codesign --sign "Developer ID Application: ..."`
6. Notarizes the DMG with `notarytool submit --wait`
7. Staples the notarization ticket with `stapler staple`
8. Creates a GitHub Release with the DMG attached
9. Computes the SHA-256 of the DMG and updates `Casks/aws-ssm-param-store-ui.rb` in the `homebrew-tap` repo
