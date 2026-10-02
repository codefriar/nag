# Nag Public Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Nag as a Developer ID–signed, notarized, stapled DMG with an original icon, an MIT license, and a one-command GitHub release.

**Architecture:**
- A `VERSION` file feeds every build.
- `scripts/release.sh` (`make dist`) archives and exports with Developer ID and hardened runtime, builds a styled DMG with `create-dmg`, notarizes it with a `notarytool` keychain profile, staples it, and verifies it with Gatekeeper.
- `scripts/publish.sh` (`make release`) checks the guard rails, tags the commit, and runs `gh release create`.
- Day-to-day builds stay ad-hoc signed.

**Tech Stack:** bash, Xcode 27 command-line tools (`xcodebuild`, `notarytool`, `stapler`, `spctl`, `codesign`, `hdiutil`, `tiffutil`), `create-dmg` (Homebrew), `gh`, Swift scripts with AppKit, and XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-01-nag-release-design.md`. It amends `docs/superpowers/specs/2026-10-01-nag-design.md`.

## Global Constraints

- Signing identity: `Developer ID Application: Kevin Poorman (745ST2PM9F)`; team `745ST2PM9F`.
- Notary profile: `NOTARY_PROFILE`, default `nag-notary`.
- Bundle ID: `com.codefriar.nagapp`. Do not change it.
- `project.yml` keeps ad-hoc signing (`CODE_SIGN_IDENTITY: "-"`) and `ENABLE_HARDENED_RUNTIME: NO`. Developer ID and hardened runtime are passed only on the `release.sh` command line.
- `VERSION` is the single source of the marketing version. The build number is `git rev-list --count HEAD`.
- Outputs: `dist/Nag-<version>[-dirty].dmg` and `dist/Nag-<version>[-dirty].dmg.sha256`. `dist/` and `build/` are gitignored.
- License: MIT, `Copyright (c) 2026 Kevin Poorman`.
- Icon: no SF Symbols anywhere in `scripts/make-icon.swift`.
- Colors:
  - Gradient: `#FF9F0A` → `#FF6B00`
  - Mark: `#FF7A00`
  - DMG background: `#F7F5F2`
  - Arrow: `#B8B2AA`
  - Caption: `#8A847C`
- DMG layout:
  - Window: 660×400
  - Icon size: 128
  - `Nag.app` at (180, 190)
  - Applications link at (480, 190)
- Never publish (push a tag or create a GitHub release) during plan execution. `make release` is run only by the user.
- Run every command from the worktree root.

## Review Focus

1. **`create-dmg` needs Automation permission to lay out the window in Finder.** On the first run macOS prompts for Terminal (or the calling app) to control Finder. If it's denied, the DMG has no layout or `create-dmg` fails. The expected behavior is a clear failure, not a silently unstyled DMG. (Task 4: the manual DMG check.)
2. **Developer ID settings must not leak into everyday builds.** After `make dist`, `make install` must still produce an ad-hoc signed app. (Task 4: the `codesign` check after dist.)
3. **Rerunning `make dist` for the same version.** The old DMG must be replaced, not cause a `create-dmg` "file exists" failure. (Task 4: running dist twice.)
4. **A dirty working tree or an unknown notary profile.** These must fail at preflight with a readable message, before any slow work. (Task 4: the preflight tests.)
5. **`make release` with a missing changelog section or no `origin`.** It must refuse *before* spending minutes on notarization. (Task 6: `publish.sh --check` runs before `dist`.)

---

### Task 1: Versioning from `VERSION`

**Files:**
- Create: `VERSION`
- Modify: `Nag/Info.plist` (`CFBundleShortVersionString`, `CFBundleVersion`)
- Modify: `project.yml` (base settings)
- Modify: `Makefile`
- Modify: `.gitignore`

**Interfaces:**
- Produces:
  - `VERSION`, containing `1.0.0` and a newline.
  - Makefile variables `VERSION`, `BUILD_NUMBER`, and `XCB_VERSION` (`MARKETING_VERSION=$(VERSION) CURRENT_PROJECT_VERSION=$(BUILD_NUMBER)`).

- [ ] **Step 1: Write the failing check**

Run: `make build && plutil -extract CFBundleShortVersionString raw build/Build/Products/Release/Nag.app/Contents/Info.plist`
Expected: prints `1.0`, the old hard-coded value. That's a failure against the target `1.0.0`.

- [ ] **Step 2: Create `VERSION`**

```
1.0.0
```

- [ ] **Step 3: Make `Nag/Info.plist` use build settings**

Replace:

```xml
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
```

with:

```xml
	<key>CFBundleShortVersionString</key>
	<string>$(MARKETING_VERSION)</string>
	<key>CFBundleVersion</key>
	<string>$(CURRENT_PROJECT_VERSION)</string>
```

- [ ] **Step 4: Add defaults in `project.yml`**

Under the top-level `settings.base`, after `ENABLE_HARDENED_RUNTIME: NO`, add:

```yaml
    MARKETING_VERSION: 0.0.0-dev
    CURRENT_PROJECT_VERSION: "1"
```

- [ ] **Step 5: Pass the version from the Makefile**

Replace the variable block at the top of `Makefile` (from `PROJECT` to `APP`) with:

```make
PROJECT      := Nag.xcodeproj
BUILD_DIR    := build
APP          := $(BUILD_DIR)/Build/Products/Release/Nag.app
VERSION      := $(shell tr -d '[:space:]' < VERSION)
BUILD_NUMBER := $(shell git rev-list --count HEAD)
XCB_VERSION  := MARKETING_VERSION=$(VERSION) CURRENT_PROJECT_VERSION=$(BUILD_NUMBER)
```

Then append ` $(XCB_VERSION)` to the end of the continuation line in both the `build` and `test` recipes, so they read:

```make
build: generate
	xcodebuild build -project $(PROJECT) -scheme Nag -configuration Release \
		-derivedDataPath $(BUILD_DIR) -destination 'platform=macOS' -quiet $(XCB_VERSION)

test: generate
	xcodebuild test -project $(PROJECT) -scheme Nag \
		-derivedDataPath $(BUILD_DIR) -destination 'platform=macOS' -quiet $(XCB_VERSION)
```

- [ ] **Step 6: Ignore `dist/`**

Append to `.gitignore`:

```gitignore
dist/
```

- [ ] **Step 7: Verify**

Run: `make build && plutil -extract CFBundleShortVersionString raw build/Build/Products/Release/Nag.app/Contents/Info.plist && plutil -extract CFBundleVersion raw build/Build/Products/Release/Nag.app/Contents/Info.plist && git rev-list --count HEAD`
Expected: `1.0.0`, then a build number that equals the commit count printed on the last line.

Run: `make test`
Expected: exit 0. Check the xcresult summary for 18 passed and 0 failed.

- [ ] **Step 8: Commit**

```bash
git add VERSION Nag/Info.plist project.yml Makefile .gitignore
git commit -m "Drive app version from VERSION file and git commit count"
```

---

### Task 2: Original speech-bubble icon

**Files:**
- Modify: `scripts/make-icon.swift` (full rewrite)
- Regenerate: `Nag/Assets.xcassets/AppIcon.appiconset/*.png` and `Contents.json`

**Interfaces:**
- Consumes: the `make icon` target, which already exists.
- Produces: an `AppIcon` set with the same filenames as before.

- [ ] **Step 1: Write the failing check**

Run: `grep -c "systemSymbolName" scripts/make-icon.swift`
Expected: `1`. The SF Symbol is still in use, so the license constraint fails.

- [ ] **Step 2: Rewrite `scripts/make-icon.swift`**

```swift
// Draws Nag's app icon: a white speech bubble with an orange "!" on an
// orange rounded square. Original artwork; no SF Symbols.
// Usage (from the repo root): swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024
let topColor = NSColor(srgbRed: 1.0, green: 0x9F / 255.0, blue: 0x0A / 255.0, alpha: 1)
let bottomColor = NSColor(srgbRed: 1.0, green: 0x6B / 255.0, blue: 0x00 / 255.0, alpha: 1)
let markColor = NSColor(srgbRed: 1.0, green: 0x7A / 255.0, blue: 0x00 / 255.0, alpha: 1)

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let catalog = repoRoot.appending(path: "Nag/Assets.xcassets")
let iconSet = catalog.appending(path: "AppIcon.appiconset")

func drawBackground() {
    // macOS icon grid: an 824-point body centered on a 1024-point canvas.
    let bodyRect = NSRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 20
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    bottomColor.setFill()
    bodyPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: topColor, ending: bottomColor)!.draw(in: bodyPath, angle: -90)
}

func drawBubble() {
    // Body: 520x400, centered horizontally, slightly above center (AppKit y is up).
    let body = NSRect(x: (canvas - 520) / 2, y: 330, width: 520, height: 400)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 110, yRadius: 110)

    // Tail: starts inside the body's bottom-left quarter and points down-left.
    // Filling both shapes in the same color renders their union.
    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: body.minX + 120, y: body.minY + 40))
    tail.line(to: NSPoint(x: body.minX + 240, y: body.minY + 40))
    tail.line(to: NSPoint(x: body.minX + 60, y: body.minY - 110))
    tail.close()

    NSColor.white.setFill()
    bodyPath.fill()
    tail.fill()
}

func drawExclamation() {
    // Bar 64x200 + 36 gap + 72 dot = 308 tall, centered on the bubble body (y = 530).
    let centerX = canvas / 2
    let barTop: CGFloat = 530 + 154
    let bar = NSRect(x: centerX - 32, y: barTop - 200, width: 64, height: 200)
    let dot = NSRect(x: centerX - 36, y: bar.minY - 36 - 72, width: 72, height: 72)

    markColor.setFill()
    NSBezierPath(roundedRect: bar, xRadius: 32, yRadius: 32).fill()
    NSBezierPath(ovalIn: dot).fill()
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    // Draw in a 1024-point coordinate space regardless of the output pixel size.
    rep.size = NSSize(width: canvas, height: canvas)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawBackground()
    drawBubble()
    drawExclamation()
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])!
}

let fileManager = FileManager.default
try fileManager.createDirectory(at: iconSet, withIntermediateDirectories: true)

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = scale == 1
            ? "icon_\(points)x\(points).png"
            : "icon_\(points)x\(points)@2x.png"
        try render(pixels: points * scale).write(to: iconSet.appending(path: filename))
        images.append([
            "filename": filename,
            "idiom": "mac",
            "scale": "\(scale)x",
            "size": "\(points)x\(points)",
        ])
    }
}

let info = ["author": "xcode", "version": 1] as [String: Any]
let encoder = { (object: Any) in
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
}
try encoder(["images": images, "info": info]).write(to: iconSet.appending(path: "Contents.json"))
try encoder(["info": info]).write(to: catalog.appending(path: "Contents.json"))
print("Wrote \(images.count) icons to \(iconSet.path)")
```

- [ ] **Step 3: Generate and check that the SF Symbol is gone**

Run: `make icon && grep -c "systemSymbolName" scripts/make-icon.swift; sips -g pixelWidth Nag/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png`
Expected:
- `Wrote 10 icons to …`
- `0` from the grep (grep exits 1, which is fine here)
- `pixelWidth: 1024`

- [ ] **Step 4: Visual check, and user approval (required by the spec)**

View `Nag/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png` (for example with the Read tool). Then view `icon_32x32.png` to check that the glyph is still legible at small size.

Expected:
- A white speech bubble with its tail at the bottom left.
- An orange "!" centered in the bubble.
- Nothing clipped.

Show the user the 1024-pixel render and **wait for their approval** before committing. If they ask for changes, adjust the constants in `drawBubble` or `drawExclamation`, regenerate, and show it again.

- [ ] **Step 5: Build and install**

Run: `make install && plutil -extract CFBundleIconName raw /Applications/Nag.app/Contents/Info.plist`
Expected: `AppIcon`.

- [ ] **Step 6: Commit**

```bash
git add scripts/make-icon.swift Nag/Assets.xcassets
git commit -m "Replace SF Symbol icon with original speech-bubble artwork"
```

---

### Task 3: DMG background

**Files:**
- Create: `scripts/make-dmg-background.swift`
- Create (generated): `scripts/dmg/background.png`, `scripts/dmg/background@2x.png`, `scripts/dmg/background.tiff`
- Modify: `Makefile` (add the `dmg-background` target)

**Interfaces:**
- Produces: `scripts/dmg/background.tiff`, a HiDPI TIFF at 660×400 points, which Task 4 consumes.

- [ ] **Step 1: Write the failing check**

Run: `test -f scripts/dmg/background.tiff && echo present || echo missing`
Expected: `missing`.

- [ ] **Step 2: Create `scripts/make-dmg-background.swift`**

```swift
// Draws the DMG window background (660x400 pt) at 1x and 2x, then combines
// them into a HiDPI TIFF for create-dmg.
// Usage (from the repo root): swift scripts/make-dmg-background.swift
import AppKit

let size = NSSize(width: 660, height: 400)
let backgroundColor = NSColor(srgbRed: 0xF7 / 255.0, green: 0xF5 / 255.0, blue: 0xF2 / 255.0, alpha: 1)
let arrowColor = NSColor(srgbRed: 0xB8 / 255.0, green: 0xB2 / 255.0, blue: 0xAA / 255.0, alpha: 1)
let captionColor = NSColor(srgbRed: 0x8A / 255.0, green: 0x84 / 255.0, blue: 0x7C / 255.0, alpha: 1)

let outputDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appending(path: "dmg")

/// Converts a Finder y coordinate (measured from the top) to AppKit's bottom-up y.
func appKitY(_ finderY: CGFloat) -> CGFloat { size.height - finderY }

func render(scale: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = size

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    backgroundColor.setFill()
    NSRect(origin: .zero, size: size).fill()

    // Arrow from the app icon (x=180) toward the Applications link (x=480), at icon height.
    let y = appKitY(190)
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 260, y: y))
    arrow.line(to: NSPoint(x: 400, y: y))
    arrow.move(to: NSPoint(x: 382, y: y + 16))
    arrow.line(to: NSPoint(x: 400, y: y))
    arrow.line(to: NSPoint(x: 382, y: y - 16))
    arrow.lineWidth = 6
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrowColor.setStroke()
    arrow.stroke()

    let caption = NSAttributedString(
        string: "Drag Nag to Applications",
        attributes: [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: captionColor,
        ]
    )
    let captionSize = caption.size()
    caption.draw(at: NSPoint(
        x: (size.width - captionSize.width) / 2,
        y: appKitY(320) - captionSize.height / 2
    ))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
let png1x = outputDir.appending(path: "background.png")
let png2x = outputDir.appending(path: "background@2x.png")
let tiff = outputDir.appending(path: "background.tiff")
try render(scale: 1).write(to: png1x)
try render(scale: 2).write(to: png2x)

let tiffutil = Process()
tiffutil.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
tiffutil.arguments = ["-cathidpicheck", png1x.path, png2x.path, "-out", tiff.path]
try tiffutil.run()
tiffutil.waitUntilExit()
guard tiffutil.terminationStatus == 0 else {
    fatalError("tiffutil failed with status \(tiffutil.terminationStatus)")
}
print("Wrote \(tiff.path)")
```

- [ ] **Step 3: Add the Makefile target**

Change the `.PHONY` line to:

```make
.PHONY: generate icon dmg-background build test install dist release clean
```

Add this after the `icon` target:

```make
dmg-background:
	swift scripts/make-dmg-background.swift
```

- [ ] **Step 4: Generate and verify**

Run: `make dmg-background && tiffutil -info scripts/dmg/background.tiff | grep -E "Image Width|Image Length"`
Expected:
- `Wrote …/scripts/dmg/background.tiff`
- Two images: 660×400 and 1320×800

- [ ] **Step 5: Visual check**

View `scripts/dmg/background@2x.png`. Expected:
- An off-white background.
- A grey right-pointing arrow centered between x≈260 and x≈400 at about 47% height.
- The caption "Drag Nag to Applications" centered near the bottom.

- [ ] **Step 6: Commit**

```bash
git add scripts/make-dmg-background.swift scripts/dmg Makefile
git commit -m "Add generated DMG window background"
```

---

### Task 4: `make dist`: archive, sign, DMG, notarize, staple

**Files:**
- Create: `scripts/ExportOptions.plist`
- Create: `scripts/release.sh` (executable)
- Modify: `Makefile` (add the `dist` target)

**Interfaces:**
- Consumes: `VERSION` (Task 1), `scripts/dmg/background.tiff` (Task 3).
- Produces:
  - `make dist`, which writes `dist/Nag-<version>[-dirty].dmg` and `.dmg.sha256`.
  - Environment variables `NOTARY_PROFILE`, `TEAM_ID`, `SIGN_IDENTITY`, `ALLOW_DIRTY`.

**Prerequisite:** the user has created the notary profile, for example with `xcrun notarytool store-credentials nag-notary --key … --key-id … --issuer …`. If `xcrun notarytool history --keychain-profile nag-notary` fails, finish Steps 1–6, then **stop and ask the user** to create the profile before Step 7.

- [ ] **Step 1: Write the failing check**

Run: `make dist`
Expected: `make: *** No rule to make target 'dist'.`

- [ ] **Step 2: Create `scripts/ExportOptions.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>destination</key>
	<string>export</string>
	<key>method</key>
	<string>developer-id</string>
	<key>signingCertificate</key>
	<string>Developer ID Application</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>teamID</key>
	<string>745ST2PM9F</string>
</dict>
</plist>
```

- [ ] **Step 3: Create `scripts/release.sh`**

```bash
#!/usr/bin/env bash
# Builds, signs, notarizes, and staples dist/Nag-<version>.dmg.
# Usage: make dist   (or scripts/release.sh from the repo root)
#
# Environment:
#   NOTARY_PROFILE  notarytool keychain profile (default: nag-notary)
#   TEAM_ID         Apple developer team (default: 745ST2PM9F)
#   SIGN_IDENTITY   Developer ID Application identity
#   ALLOW_DIRTY=1   allow a dirty working tree; the DMG gets a -dirty suffix
set -euo pipefail

cd "$(dirname "$0")/.."

NOTARY_PROFILE="${NOTARY_PROFILE:-nag-notary}"
TEAM_ID="${TEAM_ID:-745ST2PM9F}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Kevin Poorman (745ST2PM9F)}"
ALLOW_DIRTY="${ALLOW_DIRTY:-0}"

VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="$(git rev-list --count HEAD)"
WORK_DIR="build/dist"
ARCHIVE="$WORK_DIR/Nag.xcarchive"
EXPORT_DIR="$WORK_DIR/export"
STAGE_DIR="$WORK_DIR/stage"

fail() { echo "error: $*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

step "Preflight"
suffix=""
if [[ -n "$(git status --porcelain)" ]]; then
  [[ "$ALLOW_DIRTY" == "1" ]] || fail "working tree is dirty; commit first, or set ALLOW_DIRTY=1 for a test build"
  suffix="-dirty"
fi
security find-identity -v -p codesigning | grep -qF "\"$SIGN_IDENTITY\"" \
  || fail "signing identity not found in keychain: $SIGN_IDENTITY"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || fail "notarytool profile '$NOTARY_PROFILE' is missing or invalid (see README: Making a release)"
command -v create-dmg >/dev/null || fail "create-dmg not found (brew install create-dmg)"
command -v xcodegen >/dev/null || fail "xcodegen not found (brew install xcodegen)"

DMG="dist/Nag-$VERSION$suffix.dmg"
echo "Version $VERSION (build $BUILD_NUMBER) -> $DMG"

step "Archiving"
xcodegen generate --quiet
rm -rf "$WORK_DIR"
xcodebuild archive -project Nag.xcodeproj -scheme Nag -configuration Release \
  -archivePath "$ARCHIVE" -destination 'generic/platform=macOS' -quiet \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$SIGN_IDENTITY" DEVELOPMENT_TEAM="$TEAM_ID" \
  ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS=--timestamp

step "Exporting"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist scripts/ExportOptions.plist -quiet
APP="$EXPORT_DIR/Nag.app"

step "Verifying app signature"
codesign --verify --deep --strict --verbose=2 "$APP"
details="$(codesign -dv --verbose=4 "$APP" 2>&1)"
grep -q "(runtime)" <<<"$details" || fail "hardened runtime flag missing from $APP"
grep -q "Authority=Developer ID Application" <<<"$details" || fail "$APP is not signed with Developer ID"

step "Building DMG"
# Stage only the app; the export folder also holds logs and plists.
mkdir -p "$STAGE_DIR" dist
ditto "$APP" "$STAGE_DIR/Nag.app"
rm -f "$DMG"
create-dmg \
  --volname "Nag $VERSION" \
  --background scripts/dmg/background.tiff \
  --window-size 660 400 \
  --icon-size 128 \
  --icon "Nag.app" 180 190 \
  --app-drop-link 480 190 \
  --hide-extension "Nag.app" \
  --codesign "$SIGN_IDENTITY" \
  --no-internet-enable \
  "$DMG" "$STAGE_DIR/"

step "Notarizing (usually a few minutes)"
result="$(xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)"
submission_id="$(plutil -extract id raw -o - - <<<"$result")"
status="$(plutil -extract status raw -o - - <<<"$result")"
if [[ "$status" != "Accepted" ]]; then
  xcrun notarytool log "$submission_id" --keychain-profile "$NOTARY_PROFILE" >&2 || true
  fail "notarization finished with status '$status' (submission $submission_id)"
fi
echo "Accepted (submission $submission_id)"

step "Stapling and verifying"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
dmg_assessment="$(spctl -a -t open --context context:primary-signature -v "$DMG" 2>&1)" || true
echo "$dmg_assessment"
grep -q ": accepted" <<<"$dmg_assessment" || fail "Gatekeeper rejected $DMG"
grep -q "Notarized Developer ID" <<<"$dmg_assessment" || fail "$DMG is not recognised as notarized"

MOUNT_DIR="$(mktemp -d)"
detach() { hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true; rmdir "$MOUNT_DIR" 2>/dev/null || true; }
trap detach EXIT
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT_DIR" -quiet
app_assessment="$(spctl -a -t exec -v "$MOUNT_DIR/Nag.app" 2>&1)" || true
echo "$app_assessment"
grep -q ": accepted" <<<"$app_assessment" || fail "Gatekeeper rejected Nag.app inside $DMG"
detach
trap - EXIT

step "Checksum"
dmg_name="$(basename "$DMG")"
(cd dist && shasum -a 256 "$dmg_name" > "$dmg_name.sha256")
sha="$(cut -d' ' -f1 < "$DMG.sha256")"

step "Done"
echo "DMG:     $DMG"
echo "Version: $VERSION (build $BUILD_NUMBER)"
echo "SHA-256: $sha"
```

Then run: `chmod +x scripts/release.sh`

- [ ] **Step 4: Add the `dist` target to the Makefile**

Add this after the `install` target:

```make
dist:
	scripts/release.sh
```

(The `.PHONY` line already lists `dist` from Task 3.)

- [ ] **Step 5: Preflight test with a dirty tree**

Run: `touch dirty-probe && scripts/release.sh; echo exit=$?; rm -f dirty-probe`
Expected: `error: working tree is dirty; commit first, or set ALLOW_DIRTY=1 for a test build`, then `exit=1`.

- [ ] **Step 6: Preflight test with an unknown profile**

Run: `ALLOW_DIRTY=1 NOTARY_PROFILE=does-not-exist scripts/release.sh; echo exit=$?`
Expected: `error: notarytool profile 'does-not-exist' is missing or invalid (see README: Making a release)`, then `exit=1`.

- [ ] **Step 7: Commit, then run it for real** (requires the notary profile; see the Prerequisite above)

```bash
git add scripts/ExportOptions.plist scripts/release.sh Makefile
git commit -m "Add make dist: Developer ID archive, DMG, notarize, staple"
```

Run: `make dist 2>&1 | tee build/dist.log | tail -25`
Expected, ending with `==> Done` and the three summary lines:
- `Accepted (submission …)`
- `The staple and validate action worked!`
- `…: accepted` with `source=Notarized Developer ID` for the DMG
- `…/Nag.app: accepted` for the app inside the mounted DMG

macOS may ask permission for the terminal to control Finder; approve it. If `create-dmg` fails on AppleScript or Finder, report the error to the user instead of using `--skip-jenkins`.

- [ ] **Step 8: Rerun for the same version**

Run: `make dist 2>&1 | tail -5`
Expected: it succeeds again, and the previous DMG is replaced without a "file exists" error.

- [ ] **Step 9: Everyday builds are still ad-hoc**

Run: `make install && codesign -dv /Applications/Nag.app 2>&1 | grep -E "Signature=|flags="`
Expected: `Signature=adhoc`, and no `(runtime)` in the flags.

- [ ] **Step 10: Manual DMG check** (the user does this)

Run `open dist/Nag-1.0.0.dmg`. Expected:
- The window is 660×400.
- The orange Nag icon is on the left, the Applications shortcut on the right, and the arrow and caption are between them.
- The background is sharp on Retina.

Dragging to Applications and launching shows no Gatekeeper warning. `make install` will already have put an ad-hoc copy in `/Applications`, so the user can instead copy it to `~/Desktop` and launch it from there.

---

### Task 5: License, changelog, README, and original spec

**Files:**
- Create: `LICENSE`
- Create: `CHANGELOG.md`
- Modify: `README.md` (full rewrite)
- Modify: `docs/superpowers/specs/2026-10-01-nag-design.md`

**Interfaces:**
- Produces: the `CHANGELOG.md` heading format `## [<version>] - <YYYY-MM-DD>`, which Task 6 parses.

- [ ] **Step 1: Write the failing check**

Run: `test -f LICENSE && test -f CHANGELOG.md && echo ok || echo missing; grep -c "not distributed" README.md docs/superpowers/specs/2026-10-01-nag-design.md`
Expected: `missing`, then non-zero counts.

- [ ] **Step 2: Create `LICENSE`**

```
MIT License

Copyright (c) 2026 Kevin Poorman

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 3: Create `CHANGELOG.md`**

```markdown
# Changelog

All notable changes to Nag are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-10-01

### Added

- Entry window with Title, Subtitle, and Message fields. Return sends; Esc cancels.
- Notifications that stay on screen when Nag's alert style is set to Alerts, with an in-app hint and a shortcut to Notification settings.
- Runs without a Dock icon and quits after sending, so launchers like Alfred can trigger it.
- Notarized DMG for distribution.
```

- [ ] **Step 4: Rewrite `README.md`**

````markdown
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
````

- [ ] **Step 5: Update the original spec**

In `docs/superpowers/specs/2026-10-01-nag-design.md`, replace the line

```
- Personal use only; not distributed. Ad-hoc signing.
```

with

```
- Distributed publicly as a notarized DMG; see
  `2026-10-01-nag-release-design.md`. Local development builds use ad-hoc
  signing.
```

Then replace the whole `## App icon` section, from its heading up to but not including `## Error handling`, with:

```markdown
## App icon

Superseded by `2026-10-01-nag-release-design.md`. The icon is original
artwork, a white speech bubble with an orange "!" on the orange rounded
square, drawn by `scripts/make-icon.swift`. The SF Symbol icon was removed
because the SF Symbols license does not allow symbols in app icons.

```

- [ ] **Step 6: Verify**

Run: `test -f LICENSE && test -f CHANGELOG.md && echo ok; grep -c "not distributed" README.md docs/superpowers/specs/2026-10-01-nag-design.md; grep -c "SF Symbol" README.md`
Expected:
- `ok`
- `0` for both files
- `0` for the README

- [ ] **Step 7: Commit**

```bash
git add LICENSE CHANGELOG.md README.md docs/superpowers/specs/2026-10-01-nag-design.md
git commit -m "Add MIT license and changelog; rewrite README for public release"
```

---

### Task 6: `make release`: guard rails, tag, GitHub release

**Files:**
- Create: `scripts/publish.sh` (executable)
- Modify: `Makefile` (add the `release` target)

**Interfaces:**
- Consumes:
  - `VERSION`
  - `dist/Nag-<version>.dmg` and `.sha256` (Task 4)
  - the `CHANGELOG.md` heading format (Task 5)
- Produces:
  - `scripts/publish.sh --check`, which runs the guard rails only.
  - `scripts/publish.sh`, which runs the guard rails, then tags and publishes.
  - The `CHANGELOG_FILE` environment variable (default `CHANGELOG.md`), used by tests.

Ruling, ledgered at execution: the spec has `make release` run its guard rails after `dist`. This plan runs `publish.sh --check` **before** `dist` as well, so a missing changelog section or remote fails in seconds instead of after notarization. All of the spec's checks are still enforced.

- [ ] **Step 1: Write the failing check**

Run: `make release`
Expected: `make: *** No rule to make target 'release'.`

- [ ] **Step 2: Create `scripts/publish.sh`**

```bash
#!/usr/bin/env bash
# Tags v<version> and publishes dist/Nag-<version>.dmg as a GitHub release.
# Usage: make release              (guard rails, make dist, then publish)
#        scripts/publish.sh --check  (guard rails only)
#
# Environment:
#   CHANGELOG_FILE  changelog to read release notes from (default: CHANGELOG.md)
set -euo pipefail

cd "$(dirname "$0")/.."

CHANGELOG_FILE="${CHANGELOG_FILE:-CHANGELOG.md}"
VERSION="$(tr -d '[:space:]' < VERSION)"
TAG="v$VERSION"
DMG="dist/Nag-$VERSION.dmg"

fail() { echo "error: $*" >&2; exit 1; }

notes="$(mktemp)"
trap 'rm -f "$notes"' EXIT

[[ "${ALLOW_DIRTY:-0}" != "1" ]] || fail "refusing to publish with ALLOW_DIRTY=1"

awk -v heading="## [$VERSION]" '
  index($0, heading) == 1 { found = 1; next }
  found && /^## \[/ { exit }
  found { print }
' "$CHANGELOG_FILE" > "$notes"
grep -q '[^[:space:]]' "$notes" || fail "$CHANGELOG_FILE has no '## [$VERSION]' section"

git remote get-url origin >/dev/null 2>&1 || fail "no 'origin' remote; create the GitHub repo and add it first"
gh auth status >/dev/null 2>&1 || fail "gh is not logged in; run 'gh auth login'"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  fail "tag $TAG already exists locally"
fi
if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
  fail "tag $TAG already exists on origin"
fi

if [[ "${1:-}" == "--check" ]]; then
  echo "Release checks passed for $TAG"
  exit 0
fi

[[ -f "$DMG" && -f "$DMG.sha256" ]] || fail "$DMG not found; run 'make dist' first"

git tag -a "$TAG" -m "Nag $VERSION"
git push origin "$TAG"
gh release create "$TAG" "$DMG" "$DMG.sha256" --title "Nag $VERSION" --notes-file "$notes"
echo "Published $TAG"
```

Then run: `chmod +x scripts/publish.sh`

- [ ] **Step 3: Add the `release` target to the Makefile**

Add this after the `dist` target:

```make
release:
	scripts/publish.sh --check
	scripts/release.sh
	scripts/publish.sh
```

- [ ] **Step 4: Guard-rail test: `ALLOW_DIRTY`**

Run: `ALLOW_DIRTY=1 scripts/publish.sh --check; echo exit=$?`
Expected: `error: refusing to publish with ALLOW_DIRTY=1`, then `exit=1`.

- [ ] **Step 5: Guard-rail test: missing changelog section**

Run: `CHANGELOG_FILE=/dev/null scripts/publish.sh --check; echo exit=$?`
Expected: `error: /dev/null has no '## [1.0.0]' section`, then `exit=1`.

- [ ] **Step 6: Guard-rail test: no `origin` remote** (this repo has none)

Run: `scripts/publish.sh --check; echo exit=$?`
Expected: `error: no 'origin' remote; create the GitHub repo and add it first`, then `exit=1`.

- [ ] **Step 7: The release target stops before dist**

Run: `make release 2>&1 | tail -3`
Expected: the same `no 'origin' remote` error, and **no** `==> Preflight` line from `release.sh`. That shows nothing slow ran.

- [ ] **Step 8: Check the release-notes extraction**

Run: `awk -v heading="## [1.0.0]" 'index($0, heading) == 1 { found = 1; next } found && /^## \[/ { exit } found { print }' CHANGELOG.md`
Expected: the `### Added` heading and its four bullets from `CHANGELOG.md`, and nothing from other sections.

- [ ] **Step 9: Commit**

```bash
git add scripts/publish.sh Makefile
git commit -m "Add make release: guard rails, tag, and GitHub release"
```

Do **not** run `make release` for real; publishing is the user's step.
