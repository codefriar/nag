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
