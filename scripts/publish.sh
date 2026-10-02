#!/usr/bin/env bash
# Tags v<version> and publishes dist/Nag-<version>.dmg as a GitHub release.
# Usage: make release              (guard rails, make dist, then publish)
#        scripts/publish.sh --check  (guard rails only)
#
# Environment:
#   CHANGELOG_FILE  changelog to read release notes from (default: CHANGELOG.md)
#   DRY_RUN=1       run every check, then print what would be published and stop
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
[[ -z "$(git status --porcelain)" ]] || fail "working tree is dirty; commit before publishing"

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

[[ -f "$DMG" && -f "$DMG.sha256" && -f "$DMG.commit" ]] || fail "$DMG not found; run 'make dist' first"
built_from="$(tr -d '[:space:]' < "$DMG.commit")"
head="$(git rev-parse HEAD)"
[[ "$built_from" == "$head" ]] || fail "$DMG was built from $built_from but HEAD is $head; rebuild with 'make dist'"
(cd dist && shasum -a 256 -c "$(basename "$DMG").sha256" >/dev/null 2>&1) \
  || fail "checksum mismatch for $DMG; rebuild with 'make dist'"
xcrun stapler validate "$DMG" >/dev/null 2>&1 \
  || fail "$DMG has no valid notarization ticket; rebuild with 'make dist'"

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "Dry run: would tag $built_from as $TAG, push it, and release $DMG"
  exit 0
fi

git tag -a "$TAG" "$built_from" -m "Nag $VERSION"
git push origin "$TAG"
gh release create "$TAG" "$DMG" "$DMG.sha256" --title "Nag $VERSION" --notes-file "$notes"
echo "Published $TAG"
