#!/bin/zsh
# Builds Foglio.app (universal) and packages it into a compressed disk image:
#   build/Foglio-<version>.dmg   (Foglio.app + a symlink to /Applications)
#
# Usage: scripts/package.sh [--skip-build]
#
# Optional environment:
#   DEVELOPER_ID    codesigning identity, e.g. "Developer ID Application: Jane Doe (TEAMID1234)".
#                   Signs the app with the hardened runtime and a secure timestamp, then the DMG.
#   NOTARY_PROFILE  notarytool keychain profile (see `xcrun notarytool store-credentials`).
#                   Requires DEVELOPER_ID. Submits the DMG, waits, and staples the ticket.
#   DMG_FORMAT      hdiutil image format (default ULMO = LZMA, macOS 10.15+; UDZO for zlib).
#
# Only Apple tools are used (codesign, hdiutil, notarytool, stapler) — nothing third-party.
set -euo pipefail
ROOT=${0:A:h:h}
OUT=$ROOT/build
APP=$OUT/Foglio.app
FORMAT=${DMG_FORMAT:-ULMO}

if [[ "${1:-}" != "--skip-build" ]]; then
  "$ROOT/scripts/build.sh"
fi
[[ -d "$APP" ]] || { echo "✗ $APP not found — run scripts/build.sh first" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG=$OUT/Foglio-$VERSION.dmg
echo "▸ Packaging Foglio $VERSION"
echo "  $(lipo -archs "$APP/Contents/MacOS/Foglio")"

# ── Signing ──────────────────────────────────────────────────────────────────────────────
if [[ -n "${DEVELOPER_ID:-}" ]]; then
  echo "▸ Codesigning with \"$DEVELOPER_ID\" (hardened runtime)"
  codesign --force --timestamp --options runtime --sign "$DEVELOPER_ID" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
else
  [[ -n "${NOTARY_PROFILE:-}" ]] && { echo "✗ NOTARY_PROFILE requires DEVELOPER_ID" >&2; exit 1; }
  # build.sh already signs ad hoc; re-sign to be sure the bundle seal is current.
  codesign --force --sign - "$APP"
fi

# ── Disk image ───────────────────────────────────────────────────────────────────────────
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/foglio-dmg.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Foglio.app"
ln -s /Applications "$STAGE/Applications"

echo "▸ Creating $DMG ($FORMAT)"
rm -f "$DMG"
hdiutil create -quiet -volname "Foglio $VERSION" -srcfolder "$STAGE" \
  -fs HFS+ -format "$FORMAT" -ov "$DMG"
hdiutil verify -quiet "$DMG"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"
fi

# ── Notarization ─────────────────────────────────────────────────────────────────────────
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "▸ Notarizing (profile: $NOTARY_PROFILE) — this can take a few minutes"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG" || true
fi

echo "✓ $DMG"
echo "  size:   $(du -h "$DMG" | cut -f1)"
echo "  sha256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"

if [[ -z "${DEVELOPER_ID:-}" ]]; then
  cat <<'NOTE'

Note: this build is ad-hoc signed and not notarized, so Gatekeeper will block the first launch.
  • macOS 14: right-click Foglio.app → Open, then confirm.
  • macOS 15+: try to open it once, then System Settings → Privacy & Security → "Open Anyway".
  • Or, for a copy you built yourself: xattr -dr com.apple.quarantine /Applications/Foglio.app
Set DEVELOPER_ID (and NOTARY_PROFILE) to produce a signed, notarized DMG.
NOTE
elif [[ -z "${NOTARY_PROFILE:-}" ]]; then
  echo "\nNote: signed but not notarized — set NOTARY_PROFILE to notarize and staple."
fi
