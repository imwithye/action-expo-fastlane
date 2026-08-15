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

Every push to main builds and uploads to TestFlight:

```yaml
name: release

on:
  push:
    branches: [main]

jobs:
  ios:
    runs-on: macos-26
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v4

      # The action expects node_modules to exist.
      - run: npm ci

      - uses: imwithye/action-expo-fastlane@v1
        with:
          match-git-url: git@github.com:you/applecert.git
          match-password: ${{ secrets.MATCH_PASSWORD }}
          match-deploy-key: ${{ secrets.MATCH_DEPLOY_KEY }}
          asc-key-id: ${{ secrets.APP_STORE_CONNECT_KEY_ID }}
          asc-issuer-id: ${{ secrets.APP_STORE_CONNECT_ISSUER_ID }}
          asc-key-p8-base64: ${{ secrets.APP_STORE_CONNECT_KEY_P8 }}
```

That's the whole workflow. Worth adding as your project grows: a
`concurrency` group so superseded pushes cancel, an Xcode DerivedData
cache (e.g. `irgaly/xcode-cache`) for much faster archives, and an
`actions/upload-artifact` step on the `ipa-path` output if you want the
IPA downloadable from the run page.

## Prerequisites

- **A seeded match repo.** From a laptop, run `fastlane match appstore` once
  (with a Matchfile or `--git_url`) so the repo holds an Apple Distribution
  certificate and an App Store profile for your bundle id. By default CI only
  downloads (`readonly`), so anything missing fails the build instead of
  touching your Apple account. Alternatively, give CI a **write** deploy key
  and set `match-readonly: false` — then match creates or repairs missing
  certificates and profiles itself (useful when entitlements change), and no
  manual seeding is needed.
- **Repo access for CI.** Add a deploy key to the cert repo and put the
  private key in `MATCH_DEPLOY_KEY` — read-only is enough unless you use
  `match-readonly: false`. (Skip `match-deploy-key` if your runner can
  already clone the repo.)
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
| `match-readonly` | no | `true` | `false` lets match create/repair certs and profiles (needs a write key) |
| `working-directory` | no | `.` | Directory of the Expo project |
| `distribution` | no | `app-store` | `ad-hoc` exports for registered devices instead |
| `dev-client` | no | `false` | `true` archives Debug, producing an expo-dev-client build |
| `build-number` | no | `github.run_number` | CFBundleVersion for this build |
| `upload` | no | `auto` | `auto` uploads app-store builds, skips ad-hoc; `true`/`false` force |
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

- **Bring your own fastlane.** Anything the project already has wins: a
  project `fastlane/` replaces the bundled lane wholesale, a project
  `Gemfile` keeps its whole bundle (the template `Gemfile.lock` is then not
  copied either — but your Gemfile must provide `fastlane` and `cocoapods`),
  and a project `.ruby-version` picks the Ruby. The action then just
  provides Ruby, the deploy key, and the env plumbing
  (`MATCH_*`, `ASC_*`, `BUILD_NUMBER`, `UPLOAD`, `DISTRIBUTION`,
  `DEV_CLIENT`, `EXPO_PREBUILD_COMMAND`),
  and runs `bundle exec fastlane ios release`. The `ipa-path` output is
  found by searching the working directory for `*.ipa`, so a custom output
  location still works.
- **Ad-hoc builds:** `distribution: ad-hoc` signs against the cert repo's
  adhoc profile and exports an IPA installable on the devices registered in
  the profile. TestFlight is app-store-only, so the default
  `upload: auto` skips the upload for ad-hoc builds on its own. Seed
  the profile once with `fastlane match adhoc` (or use `match-readonly:
  false`), and re-run that after registering new devices —
  `fastlane match adhoc --force_for_new_devices` picks them up.
- **Dev client builds:** `dev-client: true` archives the `Debug`
  configuration instead of `Release`. Signing and export are untouched, so it
  combines with either distribution — an ad-hoc dev client for testers'
  devices, or an app-store one for TestFlight. Debug turns React Native's
  bundling phase into a no-op, so the IPA carries no JS: the app opens the
  expo-dev-client launcher and loads the bundle from a Metro server
  (`npx expo start --dev-client`) or an EAS Update branch. The project must
  depend on `expo-dev-client` (`npx expo install expo-dev-client`) — without
  it the build has no launcher and nothing to run, so the lane stops before
  archiving. The name and bundle identifier are untouched, so the dev client
  installs over the real app rather than alongside it — to tell them apart or
  keep both, set the name and `ios.bundleIdentifier` yourself from the
  exported `DEV_CLIENT` in an `app.config.js`.
- **Version bumps** (`CFBundleShortVersionString`) stay yours: set
  `expo.version` in the app repo. Only the build number is stamped per run.
