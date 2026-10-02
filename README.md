# Nag

A tiny macOS app for posting native notifications that stay on screen.
Launch it, type a title (plus an optional subtitle and message), and press Return.
Nag posts the notification and quits.

## Install

1. Download `Nag-<version>.dmg` from [Releases](../../releases).
2. Open it and drag **Nag** to **Applications**.

Nag is signed and notarized by Apple, so it opens without Gatekeeper warnings.
Requires macOS 27 or later.

## First run

1. Launch Nag and click **Allow** when macOS asks about notifications.
2. Open **System Settings → Notifications → Nag** and set the alert style to **Alerts**.
   Nag shows a hint with an **Open Settings** button until you do.
   With "Banners", notifications disappear after a few seconds.

## Using it

- **Return** sends, and **Esc** cancels. Title is required.
- In the Message field, **Option-Return** inserts a newline.
- Clicking a delivered nag opens a fresh Nag window.

## Alfred

Create a workflow with a keyword trigger connected to a **Launch Apps** action that targets `Nag.app`.
You can also use a Terminal Command or Run Script action with `open -a Nag`.

## Build from source

Requirements: Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
make test      # run the unit tests
make install   # build (ad-hoc signed) and copy Nag.app to /Applications
```

Other targets: `make build`, `make icon` (regenerate the app icon), `make dmg-background`, `make clean`.

## Making a release

One-time setup:

1. Install the tools: `brew install create-dmg gh`, then `gh auth login`.
2. Make sure a **Developer ID Application** certificate is in your keychain.
3. Store notarization credentials under the profile name `nag-notary` (or set `NOTARY_PROFILE`):

   ```sh
   xcrun notarytool store-credentials nag-notary \
     --key /path/to/AuthKey_<KEYID>.p8 --key-id <KEYID> --issuer <ISSUER-UUID>
   ```

Each release:

1. Bump `VERSION`, and add a `## [<version>] - <date>` section to `CHANGELOG.md`.
2. Commit.
3. Run `make release`. It checks the changelog, tag, and GitHub login, builds and notarizes `dist/Nag-<version>.dmg`, tags `v<version>`, pushes the tag, and creates the GitHub release with the DMG and its SHA-256.

To build the notarized DMG without publishing, run `make dist`.
`ALLOW_DIRTY=1 make dist` builds from an uncommitted tree for testing; the DMG name gets a `-dirty` suffix, and `make release` refuses to publish it.

## Troubleshooting: grey icon on notifications

Notification Center caches an app's icon the first time that bundle ID posts.
If an icon-less build ever posts, notifications keep showing a blank grey icon.
That cache survives rebuilds, re-signing, a new build number, restarting Notification Center, and clearing the system icon caches.
The only fix found was changing the bundle ID (it was changed from `com.codefriar.nag` to `com.codefriar.nagapp` for this reason).
Don't run a build without an app icon under the real bundle ID.

## License

MIT. See [LICENSE](LICENSE).
