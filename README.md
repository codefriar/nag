# Nag

A tiny macOS app for posting native notifications that stay on screen.
Launch it, type a title (plus an optional subtitle and message), and press Return.
The notification is posted and Nag quits.

## Requirements

- macOS 27, Xcode 27
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Install

```sh
make install   # builds Release and copies Nag.app to /Applications
```

Other targets: `make test`, `make build`, `make icon` (regenerate the app icon), `make clean`.

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

## Troubleshooting: grey icon on notifications

Notification Center caches an app's icon the first time that bundle ID posts.
If an icon-less build ever posts, notifications keep showing a blank grey icon.
That cache survives rebuilds, re-signing, a new build number, restarting Notification Center, and clearing the system icon caches.
The only fix found was changing the bundle ID (it was changed from `com.codefriar.nag` to `com.codefriar.nagapp` for this reason).
Don't run a build without an app icon under the real bundle ID.

## Icon

The icon is the SF Symbol `checkmark.seal.text.page`. Apple's SF Symbols license does not allow symbols in app icons.
That's acceptable here only because Nag is personal and not distributed. Replace the icon before any public release.
