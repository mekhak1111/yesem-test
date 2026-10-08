#!/usr/bin/env bash
# Builds a macOS installer (.pkg) from config.sh: one product archive with a
# component package per app (installed into /Applications) and, optionally, a
# third-party prerequisite (bundled or downloaded during install).
#
#   installer/macos/build.sh [--skip-build]
#
# Signing is taken from the environment; without it the apps keep their
# current (ad-hoc) signature and the .pkg is unsigned:
#   APP_SIGN_IDENTITY  "Developer ID Application: <Org> (<TEAMID>)"
#   PKG_SIGN_IDENTITY  "Developer ID Installer: <Org> (<TEAMID>)"
#   NOTARY_PROFILE     xcrun notarytool keychain profile (store-credentials)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${CONFIG:-$HERE/config.sh}"
# Change into the project before sourcing the config, so values derived from
# project files (VERSION from pubspec.yaml, ...) resolve; again if the config
# itself sets PROJECT_ROOT.
cd "${PROJECT_ROOT:-$(cd "$HERE/../.." && pwd)}"
# shellcheck source=config.sh
source "$CONFIG"
if [ -n "${PROJECT_ROOT:-}" ] && [ "$(pwd -P)" != "$(cd "$PROJECT_ROOT" && pwd -P)" ]; then
  cd "$PROJECT_ROOT"; source "$CONFIG"
fi
# Keep macOS from writing extended attributes as ._* AppleDouble files into payloads.
export COPYFILE_DISABLE=1

SKIP_BUILD=0
[ "${1:-}" = "--skip-build" ] && SKIP_BUILD=1
die() { echo "error: $*" >&2; exit 1; }

WORK="$OUT_DIR/work"
SCRIPTS="$WORK/scripts"
PKG="$OUT_DIR/$PKG_NAME"
RESOURCES="$HERE/resources"

check_sha() {  # file expected
  local got
  got="$(shasum -a 256 "$1" | cut -d' ' -f1)"
  [ "$got" = "$(echo "$2" | tr 'A-F' 'a-f')" ] || die "SHA-256 of $1 is $got, expected $2"
}

# Hardened runtime + timestamp, nested code first (Apple advises against --deep).
sign_app() {
  local app="$1" item flags=(--force --timestamp --options runtime --sign "$APP_SIGN_IDENTITY")
  if [ -d "$app/Contents/Frameworks" ]; then
    while IFS= read -r -d '' item; do codesign "${flags[@]}" "$item"; done \
      < <(find "$app/Contents/Frameworks" -depth \( -name '*.framework' -o -name '*.dylib' \) -print0)
  fi
  if [ -n "${ENTITLEMENTS:-}" ]; then
    codesign "${flags[@]}" --entitlements "$ENTITLEMENTS" "$app"
  else
    codesign "${flags[@]}" "$app"
  fi
}

# identifier and version of an expanded component package directory
component_info() {  # dir -> "id version"
  local info="$1/PackageInfo"
  [ -f "$info" ] || die "no PackageInfo in $1"
  local line
  line="$(tr '\n' ' ' < "$info" | grep -oE '<pkg-info[^>]*>' | head -1)"
  printf '%s %s\n' \
    "$(echo "$line" | sed -nE 's/.*[[:space:]]identifier="([^"]+)".*/\1/p')" \
    "$(echo "$line" | sed -nE 's/.*[[:space:]]version="([^"]+)".*/\1/p')"
}

# --- 1. build -------------------------------------------------------------
if [ "$SKIP_BUILD" = 0 ] && [ -n "${BUILD_COMMAND:-}" ]; then
  echo "== $BUILD_COMMAND =="
  bash -c "$BUILD_COMMAND"
fi

rm -rf "$WORK" "$PKG" "$OUT_DIR/apps"
mkdir -p "$WORK" "$OUT_DIR/apps"

# --- 2. prerequisite: verify and prepare ------------------------------------
VENDOR_REFS=()     # "id|version|file.pkg" for bundle mode
VENDOR_PKG=""      # vendor .pkg for bundle / bundle-untouched
VENDOR_APP=""      # vendor .app (from a .dmg) for bundle mode

case "$PREREQ_MODE" in
  none) ;;
  bundle|bundle-untouched)
    [ -f "$PREREQ_FILE" ] || die "missing $PREREQ_FILE (see installer/prereqs/README.md)"
    [ -n "$PREREQ_SHA256" ] || die "PREREQ_SHA256 is empty"
    check_sha "$PREREQ_FILE" "$PREREQ_SHA256"
    case "$PREREQ_FILE" in
      *.pkg) VENDOR_PKG="$PREREQ_FILE" ;;
      *.dmg)
        MNT="$WORK/vendor-dmg"; mkdir -p "$MNT"
        hdiutil attach -nobrowse -readonly -mountpoint "$MNT" "$PREREQ_FILE" >/dev/null
        trap 'hdiutil detach "$MNT" >/dev/null 2>&1 || true' EXIT
        found_pkg="$(find "$MNT" -maxdepth 2 -name '*.pkg' -print -quit)"
        found_app="$(find "$MNT" -maxdepth 2 -name '*.app' -print -quit)"
        if [ -n "$found_pkg" ]; then
          cp "$found_pkg" "$WORK/vendor-original.pkg"; VENDOR_PKG="$WORK/vendor-original.pkg"
        elif [ -n "$found_app" ] && [ "$PREREQ_MODE" = bundle ]; then
          mkdir -p "$WORK/vendor-root"; ditto "$found_app" "$WORK/vendor-root/$(basename "$found_app")"
          VENDOR_APP="$WORK/vendor-root/$(basename "$found_app")"
          codesign --verify --strict --deep "$VENDOR_APP" || die "vendor app signature invalid"
        else
          die "$PREREQ_FILE contains no usable .pkg (or .app for bundle mode)"
        fi
        hdiutil detach "$MNT" >/dev/null; trap - EXIT ;;
      *) die "PREREQ_FILE must be a .pkg or .dmg" ;;
    esac
    if [ -n "$VENDOR_PKG" ]; then
      sig="$(pkgutil --check-signature "$VENDOR_PKG" || true)"
      echo "$sig" | sed -n '1,6p'
      if [ -n "${PREREQ_TEAM_ID:-}" ]; then
        echo "$sig" | grep -q "($PREREQ_TEAM_ID)" || die "vendor package is not signed by team $PREREQ_TEAM_ID"
      elif echo "$sig" | grep -q 'no signature'; then
        echo "warning: the vendor package is unsigned; ask the vendor for a Developer ID signed, notarized package"
      fi
    fi ;;
  link)
    [ -n "$PREREQ_URL" ] && [ -n "$PREREQ_SHA256" ] || die "link mode needs PREREQ_URL and PREREQ_SHA256" ;;
  *) die "unknown PREREQ_MODE $PREREQ_MODE" ;;
esac

if [ "$PREREQ_MODE" = bundle ]; then
  if [ -n "$VENDOR_APP" ]; then
    # .app from a .dmg: wrap it, unchanged, in a component package of our own.
    pkgbuild --root "$WORK/vendor-root" --identifier "$PREREQ_ID" --version "$PREREQ_VERSION" \
      --install-location /Applications "$WORK/vendor-1.pkg" >/dev/null
    VENDOR_REFS+=("$PREREQ_ID|$PREREQ_VERSION|vendor-1.pkg")
  elif xar -tf "$VENDOR_PKG" | grep -qx 'Distribution'; then
    # Product archive: flatten each component in the order of its Distribution.
    pkgutil --expand "$VENDOR_PKG" "$WORK/vendor-x"
    n=0
    while IFS= read -r comp; do
      [ -d "$WORK/vendor-x/$comp" ] || continue
      n=$((n + 1))
      pkgutil --flatten "$WORK/vendor-x/$comp" "$WORK/vendor-$n.pkg"
      read -r cid cver < <(component_info "$WORK/vendor-x/$comp")
      VENDOR_REFS+=("$cid|$cver|vendor-$n.pkg")
    done < <(grep -oE '>#[^<]+<' "$WORK/vendor-x/Distribution" | sed -E 's/^>#//; s/<$//' | awk '!seen[$0]++')
    [ "$n" -gt 0 ] || die "no components found in $VENDOR_PKG"
    echo "note: vendor product archive flattened into $n component(s); its package signature is replaced by ours,"
    echo "      and its own Distribution checks (OS version, architecture, installation-check scripts) no longer run."
    echo "      Review $WORK/vendor-x/Distribution; use PREREQ_MODE=bundle-untouched if those checks matter."
  else
    cp "$VENDOR_PKG" "$WORK/vendor-1.pkg"
    pkgutil --expand "$VENDOR_PKG" "$WORK/vendor-c"
    read -r cid cver < <(component_info "$WORK/vendor-c")
    VENDOR_REFS+=("$cid|$cver|vendor-1.pkg")
  fi
fi

# postinstall for bundle-untouched and link (attached to the first app component)
if [ "$PREREQ_MODE" = bundle-untouched ] || [ "$PREREQ_MODE" = link ]; then
  mkdir -p "$SCRIPTS"
  {
    echo '#!/bin/bash'
    echo "# Installs $PREREQ_NAME after the app. Runs as root; \$3 = target volume."
    echo 'set -euo pipefail'
    echo "ID='$PREREQ_ID'; MIN='$PREREQ_VERSION'"
    cat <<'EOF'
have="$(pkgutil --pkg-info "$ID" 2>/dev/null | sed -n 's/^version: //p' || true)"
if [ -n "$have" ] && [ "$(printf '%s\n%s\n' "$MIN" "$have" | sort -V | head -1)" = "$MIN" ]; then
  echo "$ID $have already installed"; exit 0
fi
EOF
    if [ "$PREREQ_MODE" = bundle-untouched ]; then
      cat <<'EOF'
HERE="$(cd "$(dirname "$0")" && pwd)"
/usr/sbin/installer -pkg "$HERE/vendor.pkg" -target "$3"
EOF
    else
      echo "URL='$PREREQ_URL'; SHA256='$(echo "$PREREQ_SHA256" | tr 'A-F' 'a-f')'; TEAM='${PREREQ_TEAM_ID:-}'"
      cat <<'EOF'
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl -fsSL --retry 3 --connect-timeout 20 -o "$TMP/vendor.pkg" "$URL"
echo "$SHA256  $TMP/vendor.pkg" | shasum -a 256 -c -
if [ -n "$TEAM" ]; then pkgutil --check-signature "$TMP/vendor.pkg" | grep -q "($TEAM)"; fi
/usr/sbin/installer -pkg "$TMP/vendor.pkg" -target "$3"
EOF
    fi
  } > "$SCRIPTS/postinstall"
  chmod 755 "$SCRIPTS/postinstall"
  [ "$PREREQ_MODE" = bundle-untouched ] && cp "$VENDOR_PKG" "$SCRIPTS/vendor.pkg"
fi

# --- 3. apps: sign and make component packages -----------------------------
APP_REFS=()
first=1
for entry in "${APPS[@]}"; do
  IFS='|' read -r src id <<<"$entry"
  [ -d "$src" ] || die "missing $src (build first, or fix APPS in config.sh)"
  name="$(basename "$src")"
  ditto "$src" "$OUT_DIR/apps/$name"
  if [ -n "${APP_SIGN_IDENTITY:-}" ]; then
    echo "== signing $name =="
    sign_app "$OUT_DIR/apps/$name"
  fi
  codesign --verify --strict --deep "$OUT_DIR/apps/$name"

  root="$WORK/root-$id"; mkdir -p "$root"
  ditto --noextattr --noqtn "$OUT_DIR/apps/$name" "$root/$name"
  xattr -cr "$root"   # macOS may re-add com.apple.provenance to new files
  plist="$WORK/$id.plist"
  pkgbuild --analyze --root "$root" "$plist" >/dev/null
  # Without this, Installer "updates" a copy found elsewhere (e.g. build/) instead.
  plutil -replace 0.BundleIsRelocatable -bool NO "$plist"
  extra=()
  if [ "$first" = 1 ] && [ -d "$SCRIPTS" ]; then extra=(--scripts "$SCRIPTS"); fi
  first=0
  pkgbuild --root "$root" --component-plist "$plist" --identifier "$id" --version "$VERSION" \
    --install-location /Applications ${extra[@]+"${extra[@]}"} "$WORK/$id.pkg" >/dev/null
  APP_REFS+=("$id|$VERSION|$id.pkg")
done

# --- 4. distribution file ----------------------------------------------------
DIST="$WORK/distribution.xml"
{
  cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>$PRODUCT_NAME</title>
    <organization>$ORGANIZATION</organization>
EOF
  [ -f "$RESOURCES/welcome.html" ] && echo '    <welcome file="welcome.html" mime-type="text/html"/>'
  [ -f "$RESOURCES/conclusion.html" ] && echo '    <conclusion file="conclusion.html" mime-type="text/html"/>'
  cat <<EOF
    <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
    <domains enable_localSystem="true" enable_currentUserHome="false" enable_anywhere="false"/>
    <volume-check><allowed-os-versions><os-version min="$MIN_MACOS"/></allowed-os-versions></volume-check>
EOF
  if [ "${#VENDOR_REFS[@]}" -gt 0 ]; then
    cat <<EOF
    <script><![CDATA[
    // True when $PREREQ_NAME is missing or older than $PREREQ_VERSION.
    function vendorNeeded() {
        var have = null;
        var app = '$PREREQ_APP_PATH';
        if (app && system.files.fileExistsAtPath(app)) {
            var b = system.files.bundleAtPath(app);
            have = b ? b.CFBundleShortVersionString : null;
        } else {
            var r = system.files.plistAtPath('/var/db/receipts/$PREREQ_ID.plist');
            have = r ? r.PackageVersion : null;
        }
        return !have || system.compareVersions(have, '$PREREQ_VERSION') < 0;
    }
    ]]></script>
EOF
  fi
  echo '    <choices-outline>'
  [ "${#VENDOR_REFS[@]}" -gt 0 ] && echo '        <line choice="vendor"/>'
  echo '        <line choice="app"/>'
  echo '    </choices-outline>'
  if [ "${#VENDOR_REFS[@]}" -gt 0 ]; then
    echo "    <choice id=\"vendor\" title=\"$PREREQ_NAME\" start_selected=\"vendorNeeded()\">"
    for r in "${VENDOR_REFS[@]}"; do IFS='|' read -r id _ _ <<<"$r"; echo "        <pkg-ref id=\"$id\"/>"; done
    echo '    </choice>'
  fi
  echo "    <choice id=\"app\" title=\"$PRODUCT_NAME\">"
  for r in "${APP_REFS[@]}"; do IFS='|' read -r id _ _ <<<"$r"; echo "        <pkg-ref id=\"$id\"/>"; done
  echo '    </choice>'
  for r in ${VENDOR_REFS[@]+"${VENDOR_REFS[@]}"} "${APP_REFS[@]}"; do
    IFS='|' read -r id ver file <<<"$r"
    echo "    <pkg-ref id=\"$id\" version=\"$ver\" onConclusion=\"none\">$file</pkg-ref>"
  done
  echo '</installer-gui-script>'
} > "$DIST"

# --- 5. product archive, signing, notarization ------------------------------
sign=()
if [ -n "${PKG_SIGN_IDENTITY:-}" ]; then
  sign=(--sign "$PKG_SIGN_IDENTITY" --timestamp)
else
  echo "== installer stays unsigned (PKG_SIGN_IDENTITY not set) =="
fi
res=()
[ -d "$RESOURCES" ] && res=(--resources "$RESOURCES")
echo "== productbuild $PKG =="
productbuild --distribution "$DIST" ${res[@]+"${res[@]}"} --package-path "$WORK" \
  --version "$VERSION" ${sign[@]+"${sign[@]}"} "$PKG"

if [ -n "${NOTARY_PROFILE:-}" ]; then
  [ -n "${APP_SIGN_IDENTITY:-}" ] && [ -n "${PKG_SIGN_IDENTITY:-}" ] \
    || die "notarization needs APP_SIGN_IDENTITY and PKG_SIGN_IDENTITY"
  echo "== notarizing (usually 2-15 minutes) =="
  xcrun notarytool submit "$PKG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$PKG"
fi

strays="$(pkgutil --payload-files "$PKG" | grep -c '/\._' || true)"
[ "$strays" = 0 ] || die "$strays AppleDouble ._* files in the payload; rerun (xattrs were re-added while packaging)"
cp "$DIST" "$OUT_DIR/distribution.xml"   # kept for review
rm -rf "$WORK"
echo "Done: $PKG ($(du -h "$PKG" | cut -f1))"
pkgutil --check-signature "$PKG" || true
