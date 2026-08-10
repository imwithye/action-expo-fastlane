# action-expo-fastlane

Release an Expo iOS app from GitHub Actions: `expo prebuild`, sign with
[fastlane match](https://docs.fastlane.tools/actions/match/) against an
encrypted certificate repo, archive, and upload to TestFlight.

Point it at a certificate repo and pass the App Store Connect secrets — the
action brings its own fastlane lane, Gemfile, and Ruby version, so the app
repo needs no fastlane setup at all.

## How it works

1. `expo prebuild` regenerates the gitignored `ios/` project (CocoaPods runs
   through the bundled gems, so no global pod install is needed).
2. `match` pulls the distribution certificate and App Store profile from the
   encrypted cert repo — readonly in CI, nothing is created or revoked.
3. The generated project is flipped from automatic to manual signing, so the
   archive never mints a throwaway development certificate.
4. `build_app` archives and exports the IPA; optionally
   `upload_to_testflight`.

## Usage

```yaml
name: release

on:
  push:
    branches: [main]
  workflow_dispatch:
    inputs:
      upload:
        description: "Upload to TestFlight"
        type: boolean
        default: false

concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: true

jobs:
  ios:
    runs-on: macos-26
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v4

      # Install JS dependencies with whatever your project uses —
      # the action expects node_modules to exist.
      - uses: oven-sh/setup-bun@v2
      - run: bun install --frozen-lockfile

      # Optional but a big speedup: Xcode DerivedData + SwiftPM cache.
      - uses: irgaly/xcode-cache@v1
        with:
          key: xcode-${{ hashFiles('bun.lock') }}
          restore-keys: xcode-

      - uses: imwithye/action-expo-fastlane@v1
        with:
          match-git-url: git@github.com:you/applecert.git
          match-password: ${{ secrets.MATCH_PASSWORD }}
          match-deploy-key: ${{ secrets.MATCH_DEPLOY_KEY }}
          asc-key-id: ${{ secrets.APP_STORE_CONNECT_KEY_ID }}
          asc-issuer-id: ${{ secrets.APP_STORE_CONNECT_ISSUER_ID }}
          asc-key-p8-base64: ${{ secrets.APP_STORE_CONNECT_KEY_P8 }}
          upload: ${{ github.event_name == 'push' || inputs.upload }}

      - uses: actions/upload-artifact@v4
        with:
          name: ipa
          path: "**/ios/build/ipa/*.ipa"
          if-no-files-found: error
```

## Prerequisites

- **A seeded match repo.** From a laptop, run `fastlane match appstore` once
  (with a Matchfile or `--git_url`) so the repo holds an Apple Distribution
  certificate and an App Store profile for your bundle id. CI only ever
  downloads (`readonly`), so anything missing fails the build instead of
  touching your Apple account.
- **Repo access for CI.** Add a read-only deploy key to the cert repo and put
  the private key in `MATCH_DEPLOY_KEY`. (Skip `match-deploy-key` if your
  runner can already clone the repo.)
- **An App Store Connect API key** with App Manager access:
  `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, and the `.p8`
  base64-encoded in `APP_STORE_CONNECT_KEY_P8`
  (`base64 -i AuthKey_XXXX.p8`).
- **Identifiers in the Expo config.** `expo.ios.bundleIdentifier` and
  `expo.ios.appleTeamId` in `app.json` — or pass the `app-identifier` /
  `team-id` inputs.
- **JS dependencies installed** before the action runs (`expo` must resolve
  from `node_modules`).

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `match-git-url` | yes | | SSH URL of the encrypted certificate repo |
| `match-password` | yes | | Passphrase the cert repo is encrypted with |
| `asc-key-id` | yes | | App Store Connect API key ID |
| `asc-issuer-id` | yes | | App Store Connect API issuer ID |
| `asc-key-p8-base64` | yes | | The `.p8` key, base64-encoded |
| `match-deploy-key` | no | | SSH private key that can read the cert repo |
| `working-directory` | no | `.` | Directory of the Expo project |
| `build-number` | no | `github.run_number` | CFBundleVersion for this build |
| `upload` | no | `true` | Upload to TestFlight |
| `xcode-version` | no | runner default | Xcode version to select |
| `prebuild-command` | no | `npx expo prebuild --platform ios` | Command that generates `ios/` |
| `app-identifier` | no | from Expo config | Bundle identifier override |
| `team-id` | no | from Expo config | Apple team ID override |

## Outputs

| Output | Description |
| --- | --- |
| `ipa-path` | Absolute path of the exported IPA |

## Notes

- **`app.config.js` / `app.config.ts` projects:** the build number is stamped
  by editing `app.json` before prebuild. With a dynamic config there is no
  file to edit, so map it yourself — the action exports `BUILD_NUMBER`:

  ```js
  ios: { buildNumber: process.env.BUILD_NUMBER ?? "1" }
  ```

- **Bring your own fastlane.** Files the project already has (`fastlane/`,
  `Gemfile`, `.ruby-version`) are left untouched, so you can replace the
  bundled lane wholesale — the action then just provides Ruby, the deploy
  key, and the env plumbing, and runs `bundle exec fastlane ios release`.
- **Version bumps** (`CFBundleShortVersionString`) stay yours: set
  `expo.version` in the app repo. Only the build number is stamped per run.
