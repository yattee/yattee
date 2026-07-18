# Sparkle appcast pipeline

This directory contains the scripts and templates that sign Sparkle updates and maintain `appcast.xml` on the `gh-pages` branch. The feed is served at https://dl.yattee.stream/appcast.xml and consumed by Sparkle inside the Developer ID build of Yattee (see `Yattee/Services/Updates/SparkleUpdater.swift`).

## One-time setup

1. **Generate the EdDSA signing key** on a trusted machine (once, ever):
   ```bash
   # Location inside your Xcode DerivedData, after building Yattee once.
   SPARKLE=~/Library/Developer/Xcode/DerivedData/Yattee-*/SourcePackages/artifacts/sparkle/Sparkle/bin
   $SPARKLE/generate_keys                    # creates the keypair in Keychain
   $SPARKLE/generate_keys -p                 # prints the public key; also visible in Info.plist (SUPublicEDKey)
   ```

2. **Export the private key for CI**:
   ```bash
   $SPARKLE/generate_keys -x /tmp/sparkle_ed_private.key
   cat /tmp/sparkle_ed_private.key           # copy the single-line base64 contents
   rm /tmp/sparkle_ed_private.key            # DO NOT commit, DO NOT leave on disk
   ```
   Paste the contents into GitHub → Settings → Secrets and variables → Actions → **New repository secret** named `SPARKLE_ED_PRIVATE_KEY`.

3. **Enable GitHub Pages**: repository Settings → Pages → Source: `Deploy from a branch` → Branch: `gh-pages` / `(root)`. The first `publish_appcast` workflow run creates the branch with the seed `appcast.xml`.

4. **Confirm the public key matches `Info.plist`**: `Yattee/Info.plist`'s `SUPublicEDKey` value must equal the output of `generate_keys -p`. Any mismatch and Sparkle refuses to install updates signed with the CI's private key.

## Per-release flow (automated)

The `.github/workflows/release.yml` `publish_appcast` job:

1. Downloads the `mac-notarized-build` artifact (contains both `.zip` and `.dmg`).
2. Locates Sparkle's `sign_update` binary from the resolved SPM dependency.
3. Writes `SPARKLE_ED_PRIVATE_KEY` to a tempfile (scrubbed in `always()` step).
4. Invokes `./scripts/sparkle/update_appcast.rb` which:
   - Signs the `.zip` → `sparkle:edSignature` + `length`.
   - Prepends a new `<item>` into `gh-pages/appcast.xml` (de-duplicating if the same version+build already exists).
   - Tags beta items with `<sparkle:channel>beta</>`; stable items are untagged (Sparkle's default).
5. Commits and pushes `gh-pages`.

The `release_channel` workflow input (`beta` | `stable`, default `beta`) controls:
- `<sparkle:channel>` in the appcast item
- GitHub Release prerelease flag
- Release tag shape: `2.0.1-beta.261` vs `2.0.1-261`

## Manual ad-hoc signing

```bash
./scripts/sparkle/update_appcast.rb \
  --zip path/to/Yattee-2.0.1-macOS.zip \
  --version 2.0.1 \
  --build 261 \
  --channel beta \
  --tag 2.0.1-beta.261 \
  --sign-update-bin ~/Library/Developer/Xcode/DerivedData/Yattee-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update \
  --ed-key-file /tmp/sparkle_ed_private.key \
  --appcast appcast.xml \
  --repo yattee/yattee
```

## Verification

```bash
# After a release:
curl -sSL https://dl.yattee.stream/appcast.xml | xmllint --noout -
```
