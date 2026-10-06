#!/usr/bin/env bash
# Builds the YesEm macOS installer: one .pkg that puts both applications into
# /Applications, where Desktop finds the helper (PinCodeManagerLocator).
#
#   dist/macos/YesEm-<version>.pkg
#
# Steps:
#   1. flutter build macos --release --flavor desktop|pincode
#   2. copy both .app bundles to dist/macos/apps and sign them
#   3. pkgbuild: one component package per app
#   4. productbuild: combine them with tool/macos_installer/distribution.xml
#      (welcome/conclusion pages, macOS >= 12) into the installer
#   5. optionally notarize and staple
#
# Signing is controlled by environment variables; without them the apps keep
# Xcode's ad-hoc signature and the .pkg is unsigned. Such an installer works
# on this Mac, but Gatekeeper blocks it on a Mac that downloads it.
#
#   APP_SIGN_IDENTITY  "Developer ID Application: <Org> (<TEAMID>)"
#   PKG_SIGN_IDENTITY  "Developer ID Installer: <Org> (<TEAMID>)"
#   NOTARY_PROFILE     keychain profile created once with
#                      xcrun notarytool store-credentials <profile> \
#                        --apple-id <id> --team-id <TEAMID> --password <app-specific>
#
# Usage: tool/build_macos_installer.sh [--skip-build]
set -euo pipefail
cd "$(dirname "$0")/.."

SKIP_BUILD=0
[ "${1:-}" = "--skip-build" ] && SKIP_BUILD=1

FLUTTER="flutter"
if command -v fvm >/dev/null 2>&1 && [ -f .fvmrc ]; then
  FLUTTER="fvm flutter"
fi

# pubspec "version: 0.1.0+1" -> 0.1.0 (the +build part is CFBundleVersion).
VERSION="$(grep -m1 '^version:' pubspec.yaml | sed -E 's/^version:[[:space:]]*//; s/\+.*//')"
PRODUCTS="build/macos/Build/Products"
OUT="dist/macos"
APPS="$OUT/apps"
WORK="$OUT/work"
PKG="$OUT/YesEm-$VERSION.pkg"
ENTITLEMENTS="macos/Runner/Release.entitlements"

# role|product name|bundle id
ROLES=(
  "desktop|YesEm Desktop|global.volo.yesem.desktop"
  "pincode|YesEm Pin Code Manager|global.volo.yesem.pincode"
)

if [ "$SKIP_BUILD" = 0 ]; then
  for entry in "${ROLES[@]}"; do
    IFS='|' read -r role _ _ <<<"$entry"
    echo "== flutter build macos --release --flavor $role =="
    $FLUTTER build macos --release --flavor "$role"
  done
fi

rm -rf "$APPS" "$WORK" "$PKG"
mkdir -p "$APPS" "$WORK"

# Signs nested code first, then the bundle (Apple advises against --deep).
# Hardened runtime and a secure timestamp are required for notarization.
sign_app() {
  local app="$1" item
  local flags=(--force --timestamp --options runtime --sign "$APP_SIGN_IDENTITY")
  while IFS= read -r -d '' item; do
    codesign "${flags[@]}" "$item"
  done < <(find "$app/Contents/Frameworks" -depth \( -name '*.framework' -o -name '*.dylib' \) -print0)
  codesign "${flags[@]}" --entitlements "$ENTITLEMENTS" "$app"
}

for entry in "${ROLES[@]}"; do
  IFS='|' read -r role name id <<<"$entry"
  src="$PRODUCTS/Release-$role/$name.app"
  [ -d "$src" ] || { echo "Missing $src (run without --skip-build)" >&2; exit 1; }
  # ditto keeps symlinks, permissions and extended attributes of the bundle.
  ditto "$src" "$APPS/$name.app"

  if [ -n "${APP_SIGN_IDENTITY:-}" ]; then
    echo "== Signing $name.app with $APP_SIGN_IDENTITY =="
    sign_app "$APPS/$name.app"
  else
    echo "== $name.app keeps its ad-hoc signature (APP_SIGN_IDENTITY not set) =="
  fi
  codesign --verify --strict --deep "$APPS/$name.app"

  # pkgbuild marks bundles relocatable by default: if a copy with the same
  # bundle id exists anywhere (for example under build/), Installer updates
  # that copy instead of writing to /Applications. Turn that off.
  root="$WORK/root-$role"
  mkdir -p "$root"
  # Without extended attributes (com.apple.provenance …), which would
  # otherwise end up as ._* AppleDouble files in the payload.
  ditto --noextattr --noqtn "$APPS/$name.app" "$root/$name.app"
  plist="$WORK/component-$role.plist"
  pkgbuild --analyze --root "$root" "$plist" >/dev/null
  plutil -replace 0.BundleIsRelocatable -bool NO "$plist"
  plutil -replace 0.BundleIsVersionChecked -bool NO "$plist"

  echo "== pkgbuild $id =="
  pkgbuild \
    --root "$root" \
    --component-plist "$plist" \
    --identifier "$id" \
    --version "$VERSION" \
    --install-location /Applications \
    "$WORK/yesem-$role.pkg"
done

sed "s/@VERSION@/$VERSION/g" tool/macos_installer/distribution.xml >"$WORK/distribution.xml"

sign_pkg=()
if [ -n "${PKG_SIGN_IDENTITY:-}" ]; then
  sign_pkg=(--sign "$PKG_SIGN_IDENTITY" --timestamp)
else
  echo "== Installer package stays unsigned (PKG_SIGN_IDENTITY not set) =="
fi

echo "== productbuild $PKG =="
productbuild \
  --distribution "$WORK/distribution.xml" \
  --resources tool/macos_installer/resources \
  --package-path "$WORK" \
  --version "$VERSION" \
  ${sign_pkg[@]+"${sign_pkg[@]}"} \
  "$PKG"

if [ -n "${NOTARY_PROFILE:-}" ]; then
  [ -n "${PKG_SIGN_IDENTITY:-}" ] && [ -n "${APP_SIGN_IDENTITY:-}" ] || {
    echo "Notarization needs APP_SIGN_IDENTITY and PKG_SIGN_IDENTITY" >&2; exit 1; }
  echo "== Notarizing (can take a few minutes) =="
  xcrun notarytool submit "$PKG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$PKG"
fi

rm -rf "$WORK"
echo "Done: $PKG"
pkgutil --check-signature "$PKG" || true
