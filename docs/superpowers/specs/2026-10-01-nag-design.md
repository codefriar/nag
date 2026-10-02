# Nag — Design Spec

Date: 2026-10-01

## Purpose

A personal macOS utility for posting native notifications that stay on screen
until dismissed. Alfred (or anything that can launch an app) opens a small entry
window with Title, Subtitle, and Message fields; submitting posts the
notification and the app quits. That is the entire app.

## Requirements

- Native Swift 6 / SwiftUI app, macOS 27, built with Xcode 27.
- Launching the app (e.g. Alfred "Launch Apps", `open -a Nag`) shows the entry
  window in front, with the Title field focused.
- Fields: Title (required), Subtitle (optional), Message (optional, multi-line).
- Return sends; Esc quits without sending.
- After a successful post the app quits. Delivered notifications remain.
- No Dock icon, no app-switcher entry, no menu bar item.
- Personal use only; not distributed. Ad-hoc signing.

### "Persistent" and its limits

An app cannot force a notification to stay on screen. macOS decides this from
the app's alert style in System Settings → Notifications: "Banners" disappear
after a few seconds, "Alerts" stay until dismissed. Nag reads the current
`alertStyle` and, if it is not `.alert`, shows an inline hint with a button that
opens System Settings → Notifications. With "Alerts" set, every nag stays on
screen.

### Out of scope

- URL schemes or passing text from Alfred (pre-filling or headless posting).
- Scheduling, repeating, or re-posting notifications.
- History, persistence of past nags, menu bar UI.
- Time-sensitive or critical interruption levels.

## Architecture

### `NagApp` (app shell, composition root)

- `@main` SwiftUI `App` with a single `Window` scene titled "New Nag".
- Builds the concrete `NotificationService` and `ComposeViewModel` and wires
  them together, injecting a "finish" action that calls
  `NSApplication.shared.terminate(nil)`.
- `Info.plist` sets `LSUIElement = YES`. Because of this, the app explicitly
  activates itself on launch (`NSApp.activate()`) so the window comes to the
  front.
- Owns an object that is the `UNUserNotificationCenterDelegate`. It must be
  set before launch finishes. `willPresent` returns `[.banner, .list, .sound]`,
  because the app is in the foreground at the moment it posts and macOS would
  otherwise suppress the notification.

### `ComposeView`

- `TextField` for Title and Subtitle, a multi-line `TextField(axis: .vertical)`
  for Message.
- Title is focused on appear (`@FocusState`).
- Send button: `.keyboardShortcut(.defaultAction)`, disabled when
  `!viewModel.canSend`.
- Cancel button: `.keyboardShortcut(.cancelAction)`, calls the finish action.
- Inline banner region showing the view model's `hint` or `errorMessage`, with
  an "Open Settings" button when applicable.

### `ComposeViewModel`

`@MainActor @Observable final class`. Dependencies are injected through its
initializer:

- `notifications: any NotificationPosting`
- `finish: @MainActor () -> Void`

State:

- `title`, `subtitle`, `body: String`
- `canSend: Bool` — `title` is non-empty after trimming whitespace and
  newlines.
- `hint: Hint?` — `.deniedPermission`, `.notPersistent`, or `nil`.
- `errorMessage: String?`
- `isSending: Bool` — prevents double submission.

Operations:

- `refreshStatus() async` — calls `notifications.authorizationState()` and
  maps it to `hint`: `.denied` → `.deniedPermission`; authorized with
  `alertStyle != .alert` → `.notPersistent`; authorized with `.alert` → `nil`.
- `send() async` — guards `canSend && !isSending`. Trims all fields; passes
  `nil` for an empty subtitle or body. Calls `notifications.post(...)`. On
  success calls `finish()`. On `NotificationError.notAuthorized` sets
  `errorMessage = "Notifications are off for Nag."` and `hint =
  .deniedPermission`. On any other error sets `errorMessage` to the error's
  description. On failure the window stays open and the text is kept.
- `cancel()` — calls `finish()`.
- `openNotificationSettings()` — opens
  `x-apple.systempreferences:com.apple.Notifications-Settings.extension` via
  an injected URL opener (default `NSWorkspace.shared.open`).

### `NotificationPosting` / `NotificationService`

```swift
enum AuthorizationState: Equatable, Sendable {
    case denied
    case authorized(alertStyle: AlertStyle)
}
enum AlertStyle: Equatable, Sendable { case none, banner, alert }
enum NotificationError: Error, Equatable { case notAuthorized }

protocol NotificationPosting: Sendable {
    func authorizationState() async -> AuthorizationState
    func post(title: String, subtitle: String?, body: String?) async throws
}
```

`NotificationService` is the concrete implementation over
`UNUserNotificationCenter.current()`:

- `authorizationState()`:
  - `.notDetermined` → call `requestAuthorization(options: [.alert, .sound])`,
    then re-read the settings.
  - `.denied` → `.denied`.
  - Otherwise → `.authorized(alertStyle:)`, mapped from
    `UNAlertStyle`.
- `post(...)`:
  - Checks `authorizationState()` and throws `.notAuthorized` if denied.
  - Builds `UNMutableNotificationContent` with title, optional subtitle and
    body, and `.default` sound.
  - Adds a `UNNotificationRequest` with `identifier: UUID().uuidString` and
    `trigger: nil`, so the notification is delivered immediately and nags
    stack rather than replace each other.

## Flow

1. Launch → the app activates and the window appears with Title focused.
2. `.task { await viewModel.refreshStatus() }`. On first run macOS shows the
   permission prompt; the hint updates when it resolves.
3. Return → `send()` → post → `finish()` → the app terminates. The notification
   remains.
4. Esc → `cancel()` → the app terminates without posting.
5. Clicking a delivered notification relaunches Nag and shows a fresh entry
   window. This is acceptable default behavior; no special handling.

## Error handling

| Situation | Behavior |
|---|---|
| Blank or whitespace-only title | Send disabled |
| Permission denied | Inline error plus "Open Settings"; window stays open; text kept |
| `add` throws | Inline error with description; window stays open; text kept |
| Alert style is not "Alerts" | Non-blocking hint plus "Open Settings"; Send still works |
| Double Return while sending | Ignored via `isSending` |

## Testing

Swift Testing (`import Testing`) in the `NagTests` unit-test target, hosted by
the app. `ComposeViewModel` is tested with a `FakeNotifications`
(records posts, configurable state and error) and a finish spy:

- `canSend` for empty, whitespace-only, and valid titles.
- `send()` posts trimmed values, and nil for empty subtitle and body.
- `send()` calls `finish` exactly once on success.
- `send()` on `.notAuthorized` sets the error and hint, does not call finish,
  and keeps the text.
- `send()` on a generic error sets `errorMessage` and does not call finish.
- `send()` is a no-op when `canSend` is false.
- `refreshStatus()` maps `.denied`, `.authorized(.banner)`,
  `.authorized(.none)`, and `.authorized(.alert)` to the correct `hint`.
- `cancel()` calls finish and never posts.

Not unit-tested: `NotificationService` (a thin wrapper over the system API)
and the SwiftUI view. Verify these manually: post with "Alerts" style and
confirm it stays; confirm the banner hint appears with "Banners"; confirm
Return and Esc; confirm Alfred launch brings the window to the front.

## Project layout and build

```
project.yml           # XcodeGen spec (source of truth)
Makefile
README.md
Nag/
  NagApp.swift
  ComposeView.swift
  ComposeViewModel.swift
  NotificationService.swift   # protocol, types, concrete service
  Info.plist
NagTests/
  ComposeViewModelTests.swift
  FakeNotifications.swift
```

- `project.yml`: targets `Nag` (application) and `NagTests`
  (bundle.unit-test). Deployment target macOS 27.0, `SWIFT_VERSION 6.0` with
  strict concurrency, bundle ID `com.codefriar.nag`, `CODE_SIGN_IDENTITY "-"`
  (ad-hoc), `LSUIElement YES`.
- `Nag.xcodeproj` is gitignored, along with `build/`.
- Makefile targets:
  - `generate` — `xcodegen generate`
  - `test` — generate, then `xcodebuild test -scheme Nag -destination 'platform=macOS'`
  - `build` — generate, then a Release build into `build/`
  - `install` — build, then copy `Nag.app` to `/Applications` (replacing any
    existing copy)
- README: prerequisites (Xcode 27, `brew install xcodegen`), `make install`,
  first-run steps (allow notifications, set the style to "Alerts"), and Alfred
  setup (a "Launch Apps" action pointed at Nag, or `open -a Nag`).
