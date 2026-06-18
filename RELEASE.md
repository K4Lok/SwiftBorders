# Releasing SwiftBorder

SwiftBorder ships **directly** (Developer ID + notarization), not via the Mac App
Store — it reads other apps' windows via the Accessibility API and a private
`SkyLight` call, which the App Store sandbox forbids.

## One-time setup (requires your Apple ID)

These three steps need your Apple account login and can't be scripted away.

### 1. Create a "Developer ID Application" certificate

**Route A — Xcode (easiest):**
Settings ▸ Accounts ▸ select your team ▸ **Manage Certificates** ▸ **＋** ▸
**Developer ID Application**.

**Route B — Web portal (if Route A doesn't show the option):**
A CSR + matching private key are already prepared in `Packaging/signing/`
(the key is imported into your login keychain).
Go to <https://developer.apple.com/account/resources/certificates/list> ▸ **＋** ▸
**Developer ID Application** ▸ upload `Packaging/signing/DeveloperID.certSigningRequest`
▸ download the `.cer` ▸ double-click to install (auto-pairs with the keychain key).

> Only the account **Holder** or an **Admin** can create Developer ID certs, and
> there's a cap on how many exist per team.

### 2. Store notarization credentials

Create an app-specific password at <https://account.apple.com> (Sign-In &
Security ▸ App-Specific Passwords), then:

```bash
xcrun notarytool store-credentials "SwiftBorder-Notary" \
    --apple-id "samkalok107@gmail.com" \
    --team-id  "46298MPRUS" \
    --password "<app-specific-password>"
```

## Every release

```bash
./build-app.sh     # compile release, assemble dist/SwiftBorder.app, code-sign (Hardened Runtime)
./notarize.sh      # notarize + staple the app, build + notarize + staple the DMG
```

Outputs in `dist/`:
- `SwiftBorder.app` — signed, notarized, stapled
- `SwiftBorder.zip` — zipped app
- `SwiftBorder.dmg` — drag-to-Applications installer (also notarized)

Bump `VERSION`/`BUILD` at the top of `build-app.sh` for each release.

## Verify (on any Mac)

```bash
spctl -a -vvv dist/SwiftBorder.app     # should say: accepted, source=Notarized Developer ID
xcrun stapler validate dist/SwiftBorder.dmg
```
