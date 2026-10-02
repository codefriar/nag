# Nag Public Release — Design Spec

Date: 2026-10-01
Amends: `docs/superpowers/specs/2026-10-01-nag-design.md`

## Purpose

Make Nag publicly distributable: a Developer ID–signed, notarized, stapled DMG
published as a GitHub release. This replaces the original spec's "personal use
only, not distributed" constraint.

## Decisions

| Topic | Decision |
|---|---|
| Audience | Public (GitHub releases) |
| Icon | Replace the SF Symbol icon with an original speech bubble with "!" (SF Symbols license forbids symbols in app icons) |
| License | MIT, "Copyright (c) 2026 Kevin Poorman" |
| Notarization auth | `notarytool` keychain profile; name from `NOTARY_PROFILE`, default `nag-notary` |
| DMG tooling | `create-dmg` (Homebrew), with a generated background image |
| Publishing | `make release` tags and runs `gh release create`; run manually by the user |
| Signing identity | `Developer ID Application`, team `745ST2PM9F` |

Out of scope: CI/GitHub Actions, Sparkle or auto-update, App Store
distribution, and creating the GitHub repository or remote. The user creates
the repository and remote before the first `make release`.

## Versioning

- `VERSION` (repo root) holds the marketing version, e.g. `1.0.0`. It is the
  single source of truth.
- The build number is `git rev-list --count HEAD`.
- Every `xcodebuild` call in the Makefile passes
  `MARKETING_VERSION=$(VERSION)` and `CURRENT_PROJECT_VERSION=$(BUILD_NUMBER)`.
- `Nag/Info.plist` uses `$(MARKETING_VERSION)` for
  `CFBundleShortVersionString` and `$(CURRENT_PROJECT_VERSION)` for
  `CFBundleVersion`.
- `project.yml` base settings default to `MARKETING_VERSION: 0.0.0-dev` and
  `CURRENT_PROJECT_VERSION: "1"`, for builds started from the Xcode app.

## Release pipeline: `make dist` → `scripts/release.sh`

A bash script with `set -euo pipefail`. Configuration comes from environment
variables, with these defaults:

- `NOTARY_PROFILE=nag-notary`
- `TEAM_ID=745ST2PM9F`
- `SIGN_IDENTITY="Developer ID Application: Kevin Poorman (745ST2PM9F)"`
- `ALLOW_DIRTY=0`

Steps, stopping at the first failure:

1. **Preflight checks.** The script exits with a clear message unless all of
   these pass:
   - `git status --porcelain` is empty. With `ALLOW_DIRTY=1` this check is
     skipped, and the DMG name gets a `-dirty` suffix.
   - `security find-identity -v -p codesigning` lists `SIGN_IDENTITY`.
   - `xcrun notarytool history --keychain-profile "$NOTARY_PROFILE"` succeeds.
   - `create-dmg` and `xcodegen` are on `PATH`.
2. **Generate the project.** Run `xcodegen generate`.
3. **Archive.** `xcodebuild archive -project Nag.xcodeproj -scheme Nag
   -configuration Release -archivePath build/dist/Nag.xcarchive`, with:
   - `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`
   - `CODE_SIGN_STYLE=Manual`, `CODE_SIGN_IDENTITY="$SIGN_IDENTITY"`,
     `DEVELOPMENT_TEAM="$TEAM_ID"`
   - `ENABLE_HARDENED_RUNTIME=YES`, `OTHER_CODE_SIGN_FLAGS=--timestamp`

   These overrides are passed on the command line only. `project.yml` keeps
   ad-hoc signing and no hardened runtime, so `make build`, `make test`, and
   `make install` never touch the Developer ID key.
4. **Export.** `xcodebuild -exportArchive -archivePath build/dist/Nag.xcarchive
   -exportPath build/dist/export -exportOptionsPlist
   scripts/ExportOptions.plist`. The options plist sets
   `method: developer-id`, `signingStyle: manual`, `teamID: 745ST2PM9F`, and
   `signingCertificate: Developer ID Application`.
5. **Verify the app.**
   - `codesign --verify --deep --strict --verbose=2` on the exported `Nag.app`
     must pass.
   - `codesign -dv` output must show `flags=0x10000(runtime)` and
     `Authority=Developer ID Application`.
6. **Build the DMG.** `create-dmg` writes `dist/Nag-<version>[-dirty].dmg`
   with:
   - `--volname "Nag <version>"`
   - `--background scripts/dmg/background.tiff`
   - `--window-size 660 400`, `--icon-size 128`
   - `--icon "Nag.app" 180 190`
   - `--app-drop-link 480 190`
   - `--hide-extension "Nag.app"`
   - `--codesign "$SIGN_IDENTITY"`
   - `--no-internet-enable`

   Any existing DMG at that path is removed first.
7. **Notarize.** `xcrun notarytool submit <dmg> --keychain-profile
   "$NOTARY_PROFILE" --wait --output-format json`. The script parses `id` and
   `status`. If the status is not `Accepted`, it runs `xcrun notarytool log
   <id> --keychain-profile "$NOTARY_PROFILE"`, prints the log, and exits 1.
8. **Staple and verify.** All of these must pass:
   - `xcrun stapler staple <dmg>`, then `xcrun stapler validate <dmg>`.
   - `spctl -a -t open --context context:primary-signature -v <dmg>` reports
     `accepted` with source `Notarized Developer ID`.
   - Mount the DMG read-only (`hdiutil attach -nobrowse -readonly`) and run
     `spctl -a -t exec -v` on the `Nag.app` inside it; it must report
     `accepted`. Then detach the DMG. A `trap` ensures it is detached on
     failure.
9. **Write the checksum.** `shasum -a 256 <dmg> > <dmg>.sha256`, written
   with the bare filename so `shasum -c` works from inside `dist/`.
10. **Report.** Print the DMG path, version, build number, and SHA-256.

`dist/` and `build/` are gitignored.

## `make release` → `scripts/publish.sh`

Runs after `dist` (the Makefile dependency). The script:

1. Refuses to continue if any of these is true:
   - `ALLOW_DIRTY=1` is set; a dirty build is never published.
   - Tag `v<version>` already exists, locally or on `origin`.
   - `CHANGELOG.md` has no `## [<version>]` section.
   - `gh auth status` fails.
   - There is no `origin` remote.
2. Extracts that version's `CHANGELOG.md` section, from its heading to the
   next `## [` heading, into a temporary notes file.
3. Runs `git tag -a v<version> -m "Nag <version>"`, then
   `git push origin v<version>`.
4. Runs `gh release create v<version> dist/Nag-<version>.dmg
   dist/Nag-<version>.dmg.sha256 --title "Nag <version>" --notes-file
   <notes>`.

## Icon

`scripts/make-icon.swift` is rewritten; the SF Symbol is no longer used.

- **Background:** unchanged. An 824-point rounded square on a 1024-point
  canvas, corner radius 185, a vertical gradient `#FF9F0A` → `#FF6B00`, and a
  drop shadow.
- **Glyph:** a white speech bubble built from `NSBezierPath`.
  - The body is a rounded rectangle about 520×400 points, corner radius about
    110, centered horizontally and slightly above center.
  - A triangular tail, about 110 points tall, comes off the bottom-left
    quarter of the body and points down-left. It is unioned into one path
    with the body.
- **Mark:** an orange (`#FF7A00`) "!" inside the bubble, drawn as shapes, not
  text.
  - A vertical rounded bar, about 64×200 points with fully rounded ends.
  - A circular dot, about 72 points in diameter, below the bar with a gap of
    about 36 points.
- **Output:** the same 10 PNG sizes plus `Contents.json` in
  `Nag/Assets.xcassets/AppIcon.appiconset/`.
- **Approval:** the user reviews the 1024-pixel render before it is
  committed.

## DMG background

`scripts/make-dmg-background.swift` draws a 660×400-point image at 1x and 2x:

- Background color `#F7F5F2`.
- A light-grey (`#B8B2AA`) arrow, about 6 points thick, from x≈260 to x≈400
  at icon height. Coordinates are measured from the top, to match Finder,
  with y=190.
- The caption "Drag Nag to Applications" in the system font, 15 points,
  color `#8A847C`, centered at y≈320.

It writes `background.png` and `background@2x.png`, then combines them with
`tiffutil -cathidpicheck` into `scripts/dmg/background.tiff`. All three files
are committed. `make dmg-background` regenerates them.

## Documentation and licensing

- `LICENSE`: the MIT license text, "Copyright (c) 2026 Kevin Poorman".
- `CHANGELOG.md`: Keep a Changelog format, with `## [1.0.0] - YYYY-MM-DD`
  listing the initial features. The date is set when releasing.
- `README.md`, rewritten for public readers:
  - What Nag is.
  - Install: download the DMG from Releases and drag Nag to Applications.
  - First run: allow notifications and set the style to Alerts.
  - Alfred setup.
  - Build from source: `make install` (ad-hoc).
  - "Making a release": a one-time `notarytool store-credentials`, then bump
    `VERSION`, update `CHANGELOG.md`, commit, and `make release`.
  - Troubleshooting: the grey notification icon.
  - The SF Symbols license note is removed.
- `docs/superpowers/specs/2026-10-01-nag-design.md`: the "Personal use only;
  not distributed. Ad-hoc signing." requirement and the icon licensing
  paragraph are updated to point at this spec.

## Testing and verification

The release pipeline is shell orchestration of Apple tools, so it is verified
by running it, not by unit tests:

- **`make dist` with `ALLOW_DIRTY=1` on a working tree:** completes and
  produces a notarized, stapled DMG, and all step 5 and step 8 checks pass.
  This requires the user's notary profile to exist.
- **`make dist` with a dirty tree and no `ALLOW_DIRTY`:** fails at preflight
  with a clear message.
- **`make dist` with `NOTARY_PROFILE=does-not-exist`:** fails at preflight
  with a clear message.
- **Manual check:** open the DMG and confirm the window layout, background,
  and icon. Drag Nag to Applications and launch it; Gatekeeper must not
  warn.
- **`make release`:** the user runs it. Its guard rails (existing tag,
  missing changelog section, `ALLOW_DIRTY`) are checked by running it in
  those states before the first real release.
- **Existing workflow:** `make test` stays green, and `make install` still
  produces an ad-hoc signed app.

**Known risk:** Notification Center may keep showing the old SF Symbol icon
for `com.codefriar.nagapp` on the developer's Mac (see the README
troubleshooting section). New installs are unaffected. This is checked after
install and noted, not fixed with another bundle ID change.
