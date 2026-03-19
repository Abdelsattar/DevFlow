# Code Signing & Notarization (Phase D)

This guide covers signing and notarizing DevFlow releases so users can open the app without any Gatekeeper warning. No credentials ever touch the repository — everything flows through GitHub Actions secrets.

**Prerequisites:** An active [Apple Developer Program](https://developer.apple.com/programs/) membership ($99/year).

---

## Overview

| Step | Where | What |
|------|-------|------|
| 1 | Your Mac | Export Developer ID certificate as `.p12` |
| 2 | appleid.apple.com | Generate an app-specific password |
| 3 | GitHub → Settings → Secrets | Add 5 encrypted secrets |
| 4 | `release.yml` + `ExportOptions.plist` | Update workflow to sign & notarize |

---

## Step 1 — Export your Developer ID certificate

1. Open **Keychain Access** on your Mac
2. Select the **login** keychain → **My Certificates** category
3. Find **Developer ID Application: Your Name (XXXXXXXXXX)** — the 10-character ID in parentheses is your Team ID, note it down
4. Right-click the certificate → **Export "Developer ID Application: ..."**
5. Save as `certificate.p12` somewhere outside the repo (e.g. `~/Desktop/certificate.p12`)
6. Set a strong password when prompted — you'll need it in Step 3
7. Convert to Base64 and copy to clipboard:

```bash
base64 -i ~/Desktop/certificate.p12 | pbcopy
```

8. Delete `certificate.p12` from your Desktop after copying — you don't need the file anymore

---

## Step 2 — Generate an app-specific password

Apple requires a dedicated password for notarization (not your Apple ID password).

1. Go to [appleid.apple.com](https://appleid.apple.com)
2. Sign in → **Sign-In and Security** → **App-Specific Passwords**
3. Click **+** → name it `DevFlow CI`
4. Copy the generated password — **you only see it once**

---

## Step 3 — Add secrets to GitHub

Go to **github.com/Abdelsattar/DevFlow** → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

Add all 5 secrets:

| Secret name | Value | Where to get it |
|-------------|-------|-----------------|
| `APPLE_CERTIFICATE` | Base64 string from Step 1 | Clipboard after running `base64` command |
| `APPLE_CERTIFICATE_PASSWORD` | Password you set on the `.p12` | What you typed in Step 1 |
| `APPLE_TEAM_ID` | 10-character Team ID | Parentheses in the certificate name |
| `APPLE_APPLE_ID` | Your Apple ID email | Your Apple account |
| `APPLE_APP_PASSWORD` | App-specific password | Generated in Step 2 |

---

## Step 4 — Update the workflow and ExportOptions

### 4a. `ExportOptions.plist`

Replace the current content with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>

    <key>signingStyle</key>
    <string>manual</string>

    <key>signingCertificate</key>
    <string>Developer ID Application</string>

    <key>stripSwiftSymbols</key>
    <true/>

    <key>compileBitcode</key>
    <false/>
</dict>
</plist>
```

### 4b. `.github/workflows/release.yml`

Replace the Archive step and add signing, notarization, and stapling steps:

```yaml
      # ── 3. Import signing certificate ──────────────────────────────────────
      - name: Import certificate
        env:
          CERTIFICATE_BASE64: ${{ secrets.APPLE_CERTIFICATE }}
          CERTIFICATE_PASSWORD: ${{ secrets.APPLE_CERTIFICATE_PASSWORD }}
        run: |
          KEYCHAIN_PATH="$RUNNER_TEMP/devflow-signing.keychain-db"
          KEYCHAIN_PASSWORD=$(openssl rand -base64 16)

          # Create a temporary keychain
          security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

          # Import the certificate
          echo "$CERTIFICATE_BASE64" | base64 --decode > "$RUNNER_TEMP/certificate.p12"
          security import "$RUNNER_TEMP/certificate.p12" \
            -P "$CERTIFICATE_PASSWORD" \
            -A -t cert -f pkcs12 \
            -k "$KEYCHAIN_PATH"

          # Make the keychain available to codesign
          security list-keychain -d user -s "$KEYCHAIN_PATH"

      # ── 4. Archive ─────────────────────────────────────────────────────────
      - name: Archive
        env:
          TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
        run: |
          xcodebuild archive \
            -scheme DevFlow \
            -archivePath "$RUNNER_TEMP/DevFlow.xcarchive" \
            "CODE_SIGN_IDENTITY=Developer ID Application" \
            "DEVELOPMENT_TEAM=$TEAM_ID" \
            CODE_SIGN_STYLE=Manual \
            SKIP_INSTALL=NO \
            BUILD_LIBRARY_FOR_DISTRIBUTION=NO

      # ── 5. Export .app ─────────────────────────────────────────────────────
      - name: Export app
        run: |
          xcodebuild -exportArchive \
            -archivePath "$RUNNER_TEMP/DevFlow.xcarchive" \
            -exportPath "$RUNNER_TEMP/DevFlowExport" \
            -exportOptionsPlist ExportOptions.plist

      # ── 6. Package as .dmg ─────────────────────────────────────────────────
      - name: Create DMG
        run: |
          APP_PATH="$RUNNER_TEMP/DevFlowExport/DevFlow.app"
          DMG_PATH="$RUNNER_TEMP/DevFlow-${{ github.ref_name }}.dmg"
          STAGING="$RUNNER_TEMP/dmg-staging"
          mkdir -p "$STAGING"
          cp -R "$APP_PATH" "$STAGING/DevFlow.app"
          ln -s /Applications "$STAGING/Applications"
          hdiutil create \
            -volname "DevFlow ${{ github.ref_name }}" \
            -srcfolder "$STAGING" \
            -ov -format UDZO \
            "$DMG_PATH"
          echo "DMG_PATH=$DMG_PATH" >> "$GITHUB_ENV"

      # ── 7. Notarize ────────────────────────────────────────────────────────
      - name: Notarize DMG
        env:
          APPLE_ID: ${{ secrets.APPLE_APPLE_ID }}
          APP_PASSWORD: ${{ secrets.APPLE_APP_PASSWORD }}
          TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
        run: |
          xcrun notarytool submit "$DMG_PATH" \
            --apple-id "$APPLE_ID" \
            --password "$APP_PASSWORD" \
            --team-id "$TEAM_ID" \
            --wait

      # ── 8. Staple ──────────────────────────────────────────────────────────
      - name: Staple notarization ticket
        run: xcrun stapler staple "$DMG_PATH"

      # ── 9. Clean up keychain ────────────────────────────────────────────────
      - name: Clean up keychain
        if: always()
        run: security delete-keychain "$RUNNER_TEMP/devflow-signing.keychain-db"
```

Also update the release notes body to remove the Gatekeeper warning:

```yaml
          body: |
            ## DevFlow ${{ github.ref_name }}

            ### Install

            1. Download **DevFlow-${{ github.ref_name }}.dmg** below.
            2. Open the DMG and drag **DevFlow.app** to `/Applications`.

            ### What's new

            See [ROADMAP.md](doc/ROADMAP.md) for the full development plan.
```

---

## Verification

After the first signed release, verify everything worked:

```bash
# Check the app is signed
codesign --verify --deep --strict DevFlow.app
codesign -dv --verbose=4 DevFlow.app | grep TeamIdentifier

# Check the DMG is notarized
spctl --assess --type open --context context:primary-signature DevFlow.app
```

---

## Security notes

- The `.p12` certificate file should never be committed to the repo — delete it from your Mac after adding the secret to GitHub
- GitHub secrets are encrypted at rest and never appear in workflow logs
- The temporary keychain created during CI is deleted at the end of every job (`if: always()` ensures cleanup even on failure)
- App-specific passwords can be revoked at [appleid.apple.com](https://appleid.apple.com) without affecting your main Apple ID
