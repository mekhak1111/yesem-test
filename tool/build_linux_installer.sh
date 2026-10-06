#!/usr/bin/env bash
# Builds the YesEm Linux installer: one Debian package that puts both
# applications under /opt/yesem, where Desktop finds the helper
# (PinCodeManagerLocator).
#
#   dist/linux/yesem_<version>_<arch>.deb
#
# Steps:
#   1. tool/build_desktop_bundles.sh release (both flavors)
#   2. stage the package root: /opt/yesem/{desktop,pincode}, the
#      /usr/bin/yesem-desktop symlink, a launcher and icons for Desktop,
#      copyright and changelog
#   3. dpkg-shlibdeps: compute Depends from the binaries and plugin libraries,
#      so the package names match the Ubuntu release that builds it
#   4. DEBIAN/control from tool/linux_installer/control.in
#   5. dpkg-deb --build --root-owner-group
#
# The package is not signed; an APT repository signs its index later.
#
# Version: pubspec "0.1.0+1" becomes "0.1.0-1" (the +build number is the
# Debian revision). YESEM_DEB_VERSION overrides it, e.g. to test an upgrade.
# Architecture: dpkg --print-architecture of the building machine (arm64,
# amd64); Flutter cannot cross-build Linux desktop.
#
# Usage: tool/build_linux_installer.sh [--skip-build]
set -euo pipefail
cd "$(dirname "$0")/.."

SKIP_BUILD=0
[ "${1:-}" = "--skip-build" ] && SKIP_BUILD=1

for tool in dpkg-deb dpkg-shlibdeps dpkg strip gzip; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Missing $tool (apt install dpkg-dev binutils)" >&2; exit 1; }
done

PUBSPEC_VERSION="$(grep -m1 '^version:' pubspec.yaml | sed -E 's/^version:[[:space:]]*//')"
VERSION="${YESEM_DEB_VERSION:-${PUBSPEC_VERSION/+/-}}"
ARCH="$(dpkg --print-architecture)"
PACKAGE="yesem"
APP_ID="global.volo.yesem.desktop"
TEMPLATES="tool/linux_installer"
ICONS="macos/Runner/Assets.xcassets/AppIcon.appiconset"
OUT="dist/linux"
WORK="$OUT/deb"
# dpkg-shlibdeps treats libraries below debian/<package> as part of the
# package being built, which is what the bundled Flutter engine and plugin
# libraries are; so the staging root lives there.
ROOT="$WORK/debian/$PACKAGE"
DEB="$OUT/${PACKAGE}_${VERSION}_${ARCH}.deb"

if [ "$SKIP_BUILD" = 0 ]; then
  tool/build_desktop_bundles.sh release
fi
for role in desktop pincode; do
  [ -x "$OUT/$role/yesem-$role" ] || { echo "Missing $OUT/$role/yesem-$role (run without --skip-build)" >&2; exit 1; }
done

echo "== Staging $PACKAGE $VERSION ($ARCH) =="
rm -rf "$WORK" "$DEB"
mkdir -p "$ROOT/DEBIAN" "$ROOT/opt/yesem" "$ROOT/usr/bin" \
  "$ROOT/usr/share/applications" "$ROOT/usr/share/doc/$PACKAGE" \
  "$ROOT/usr/share/lintian/overrides"

for role in desktop pincode; do
  cp -R "$OUT/$role" "$ROOT/opt/yesem/$role"
done
# Release builds leave the runner and the plugin libraries with symbols;
# the Flutter engine and the AOT snapshot are already stripped.
find "$ROOT/opt/yesem" -type f \( -name 'yesem-*' -o -name '*.so' \) \
  -exec sh -c 'file -b "$1" | grep -q "not stripped" && strip --strip-unneeded "$1"' _ {} \;

# Desktop resolves the symlink (Platform.resolvedExecutable) and then looks
# in the sibling pincode/ folder, so the helper is found either way.
ln -s /opt/yesem/desktop/yesem-desktop "$ROOT/usr/bin/yesem-desktop"

# Launcher for Desktop only; the helper is started by Desktop.
install -m 644 "$TEMPLATES/$APP_ID.desktop" "$ROOT/usr/share/applications/$APP_ID.desktop"
for size in 16 32 64 128 256 512; do
  install -D -m 644 "$ICONS/app_icon_$size.png" \
    "$ROOT/usr/share/icons/hicolor/${size}x${size}/apps/$APP_ID.png"
done

install -m 644 "$TEMPLATES/copyright" "$ROOT/usr/share/doc/$PACKAGE/copyright"
sed -e "s/@VERSION@/$VERSION/g" -e "s/@PUBSPEC_VERSION@/$PUBSPEC_VERSION/g" \
  -e "s/@DATE@/$(date -R)/g" "$TEMPLATES/changelog.in" \
  | gzip -9n > "$ROOT/usr/share/doc/$PACKAGE/changelog.gz"
install -m 644 "$TEMPLATES/lintian-overrides" "$ROOT/usr/share/lintian/overrides/$PACKAGE"

# Policy permissions: directories 755, files 644, programs 755.
find "$ROOT" -type d -exec chmod 755 {} +
find "$ROOT" -type f -exec chmod 644 {} +
chmod 755 "$ROOT/opt/yesem/desktop/yesem-desktop" "$ROOT/opt/yesem/pincode/yesem-pincode"

echo "== dpkg-shlibdeps =="
# dpkg-shlibdeps wants a debian/control naming the package; a minimal one is
# enough, the real control file is written below.
printf 'Source: %s\n\nPackage: %s\nArchitecture: any\n' "$PACKAGE" "$PACKAGE" > "$WORK/debian/control"
mapfile -t ELF_FILES < <(cd "$WORK" && find "debian/$PACKAGE/opt" -type f \
  \( -name 'yesem-*' -o -name '*.so' \) | sort)
SHLIBDEPS_ARGS=()
for elf in "${ELF_FILES[@]}"; do
  case "$elf" in
    */yesem-*) SHLIBDEPS_ARGS+=(-e "$elf") ;;   # executables
    *) SHLIBDEPS_ARGS+=("$elf") ;;               # shared libraries
  esac
done
# Only "symbol not found" warnings matter here. The over-linking ones are
# caused by Flutter's pkg-config GTK flags (every GTK library is on the link
# line whether the runner calls into it or not), and the two notes about
# private libraries without a version in their name are expected for the
# bundled engine and plugins.
DEPENDS="$(cd "$WORK" && dpkg-shlibdeps -O --warnings=symbol-not-found "${SHLIBDEPS_ARGS[@]}" \
  2> >(grep -vE 'should already be installed in their package|cannot extract name and version' >&2) \
  | sed -n 's/^shlibs:Depends=//p')"
[ -n "$DEPENDS" ] || { echo "dpkg-shlibdeps produced no Depends" >&2; exit 1; }
echo "Depends: $DEPENDS"
rm -f "$WORK/debian/control" "$WORK/debian/$PACKAGE.substvars"

INSTALLED_SIZE="$(du -sk --exclude=DEBIAN "$ROOT" | cut -f1)"
sed -e "s/@VERSION@/$VERSION/" -e "s/@ARCH@/$ARCH/" \
  -e "s/@INSTALLED_SIZE@/$INSTALLED_SIZE/" -e "s|@DEPENDS@|$DEPENDS|" \
  "$TEMPLATES/control.in" > "$ROOT/DEBIAN/control"
chmod 755 "$ROOT/DEBIAN"

echo "== dpkg-deb $DEB =="
dpkg-deb --build --root-owner-group "$ROOT" "$DEB"
rm -rf "$WORK"
echo "Done: $DEB"
dpkg-deb --info "$DEB"
