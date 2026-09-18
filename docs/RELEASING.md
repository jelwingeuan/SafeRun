# Releasing SafeRun

This guide creates a public, signed and notarized `SafeRun-1.0.0.dmg`. Never distribute the `--unsigned` diagnostic output.

## Prerequisites

- A Developer ID Application certificate installed locally, or exported as a password-protected `.p12` for GitHub Actions.
- An App Store Connect API key with notarization access: key ID, issuer ID, and the private `.p8` file.
- A clean checkout with `version.env`, `CHANGELOG.md`, and the release tag all using the same marketing version.

## Local release

Set the certificate's exact Keychain identity and your API-key details, then run:

```sh
export APP_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export APPLE_API_KEY_ID='ABC123DEFG'
export APPLE_API_ISSUER_ID='00000000-0000-0000-0000-000000000000'
export APPLE_API_KEY_PATH="$PWD/AuthKey_ABC123DEFG.p8"
Scripts/build_release.sh
```

The command builds arm64 and x86_64, signs with hardened runtime, submits the app and DMG for notarization, staples both artifacts, mounts and verifies the DMG, and writes:

```text
dist/SafeRun-1.0.0/SafeRun-1.0.0.dmg
dist/SafeRun-1.0.0/SafeRun-1.0.0.dmg.sha256
```

Do not use `--unsigned` for publication. It is an intentional local-only diagnostic mode.

## GitHub release

Configure these repository Actions secrets:

- `MACOS_CERTIFICATE`: base64-encoded Developer ID Application `.p12`
- `MACOS_CERTIFICATE_PASSWORD`: its export password
- `APPLE_API_KEY_ID`: App Store Connect API key ID
- `APPLE_API_ISSUER_ID`: App Store Connect issuer ID
- `APPLE_API_KEY`: the complete `.p8` key content

After CI passes, create and push an annotated version tag:

```sh
git tag -a v1.0.0 -m 'SafeRun 1.0.0'
git push origin v1.0.0
```

The release workflow rejects a tag whose version does not exactly match `version.env`, runs the test suite, imports the temporary certificate, runs the signed release script, and publishes the DMG and SHA-256 checksum using GitHub's release notes.

## Final checklist

- Verify the installed app launches on both Apple Silicon and Intel macOS 14+ hardware.
- Verify Gatekeeper accepts the downloaded DMG and the app after stapling.
- Confirm the release checksum matches the uploaded DMG.
- Test real planning with a disposable folder and a non-production API key.
- Review the accepted notarization logs before announcing the release.
