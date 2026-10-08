#!/usr/bin/env bash
# Builds a Debian/Ubuntu package from config.sh, plus, with a prerequisite in
# bundle or link mode, a release folder with install.sh (and a self-extracting
# .run when makeself is installed).
#
#   installer/linux/build.sh [--skip-build]
#
# A .deb can't install another .deb from inside itself (dpkg holds its lock
# while our package installs), so the prerequisite is declared in Depends and
# apt installs both in one transaction.
#
# Needs: dpkg-dev (dpkg-deb, dpkg-shlibdeps), binutils (strip), file; optional: makeself, lintian.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${CONFIG:-$HERE/config.sh}"
# Into the project first, so config values derived from project files resolve.
cd "${PROJECT_ROOT:-$(cd "$HERE/../.." && pwd)}"
# shellcheck source=config.sh
source "$CONFIG"
if [ -n "${PROJECT_ROOT:-}" ] && [ "$(pwd -P)" != "$(cd "$PROJECT_ROOT" && pwd -P)" ]; then
  cd "$PROJECT_ROOT"; source "$CONFIG"
fi

SKIP_BUILD=0
[ "${1:-}" = "--skip-build" ] && SKIP_BUILD=1
die() { echo "error: $*" >&2; exit 1; }
for t in dpkg-deb dpkg-shlibdeps dpkg strip file sha256sum; do
  command -v "$t" >/dev/null || die "missing $t (sudo apt install dpkg-dev binutils file)"
done

ARCH="$(dpkg --print-architecture)"
WORK="$OUT_DIR/deb"
PKGROOT="$WORK/debian/$PACKAGE"   # dpkg-shlibdeps treats libraries below debian/<pkg> as ours
DEB_NAME="${PACKAGE}_${VERSION}_${ARCH}.deb"
DEB="$OUT_DIR/$DEB_NAME"

if [ "$SKIP_BUILD" = 0 ] && [ -n "${BUILD_COMMAND:-}" ]; then
  echo "== $BUILD_COMMAND =="
  bash -c "$BUILD_COMMAND"
fi

echo "== staging $PACKAGE $VERSION ($ARCH) =="
rm -rf "$WORK" "$DEB"
mkdir -p "$PKGROOT/DEBIAN" "$PKGROOT$INSTALL_ROOT" "$PKGROOT/usr/share/doc/$PACKAGE"

for entry in "${APPS[@]}"; do
  IFS='|' read -r src sub exe <<<"$entry"
  [ -x "$src/$exe" ] || die "missing $src/$exe (build first, or fix APPS)"
  mkdir -p "$PKGROOT$INSTALL_ROOT/$sub"
  cp -R "$src/." "$PKGROOT$INSTALL_ROOT/$sub/"
done
# Strip symbols from our ELF files (no-op for already stripped ones).
find "$PKGROOT$INSTALL_ROOT" -type f \( -perm -u+x -o -name '*.so*' \) -print0 |
  while IFS= read -r -d '' f; do
    file -b "$f" | grep -q 'ELF.*not stripped' && strip --strip-unneeded "$f" || true
  done

for link in ${BIN_LINKS[@]+"${BIN_LINKS[@]}"}; do
  IFS='|' read -r name target <<<"$link"
  mkdir -p "$PKGROOT/usr/bin"
  ln -s "$INSTALL_ROOT/$target" "$PKGROOT/usr/bin/$name"
done
if [ -n "${DESKTOP_FILE:-}" ]; then
  install -D -m 644 "$DESKTOP_FILE" "$PKGROOT/usr/share/applications/$(basename "$DESKTOP_FILE")"
fi
for icon in ${ICONS[@]+"${ICONS[@]}"}; do
  IFS='|' read -r size png <<<"$icon"
  install -D -m 644 "$png" "$PKGROOT/usr/share/icons/hicolor/${size}x${size}/apps/$ICON_NAME.png"
done
if [ -n "${COPYRIGHT_FILE:-}" ]; then
  install -m 644 "$COPYRIGHT_FILE" "$PKGROOT/usr/share/doc/$PACKAGE/copyright"
else
  echo "warning: COPYRIGHT_FILE not set; writing a minimal copyright file (add third-party notices, e.g. Flutter's BSD license)"
  printf 'Packaged by %s.\n' "$MAINTAINER" > "$PKGROOT/usr/share/doc/$PACKAGE/copyright"
fi

find "$PKGROOT" -type d -exec chmod 755 {} +
find "$PKGROOT" -type f ! -perm -u+x -exec chmod 644 {} +
find "$PKGROOT" -type f -perm -u+x -exec chmod 755 {} +

echo "== dpkg-shlibdeps =="
printf 'Source: %s\n\nPackage: %s\nArchitecture: any\n' "$PACKAGE" "$PACKAGE" > "$WORK/debian/control"
mapfile -t ELF < <(cd "$WORK" && find "debian/$PACKAGE$INSTALL_ROOT" -type f \( -perm -u+x -o -name '*.so*' \) \
  -exec sh -c 'file -b "$1" | grep -q ELF && echo "$1"' _ {} \; | sort)
ARGS=()
for f in ${ELF[@]+"${ELF[@]}"}; do
  case "$f" in *.so|*.so.*) ARGS+=("$f") ;; *) ARGS+=(-e "$f") ;; esac
done
DEPENDS=""
if [ "${#ARGS[@]}" -gt 0 ]; then
  # Keep only "symbol not found" warnings: over-linking notes (common with GTK
  # pkg-config flags) and notes about unversioned private libraries are noise.
  DEPENDS="$(cd "$WORK" && dpkg-shlibdeps -O --warnings=1 "${ARGS[@]}" \
    2> >(grep -vE 'should already be installed in their package|cannot extract name and version' >&2) \
    | sed -n 's/^shlibs:Depends=//p')"
fi
rm -f "$WORK/debian/control" "$WORK/debian/$PACKAGE.substvars"
add_dep() { [ -n "$1" ] || return 0; if [ -n "$DEPENDS" ]; then DEPENDS="$DEPENDS, $1"; else DEPENDS="$1"; fi; }
[ "$PREREQ_MODE" != none ] && add_dep "$PREREQ_PACKAGE (>= $PREREQ_MIN_VERSION)"
add_dep "${EXTRA_DEPENDS:-}"
echo "Depends: ${DEPENDS:-<none>}"

{
  echo "Package: $PACKAGE"
  echo "Version: $VERSION"
  echo "Architecture: $ARCH"
  echo "Maintainer: $MAINTAINER"
  echo "Installed-Size: $(du -sk --exclude=DEBIAN "$PKGROOT" | cut -f1)"
  [ -n "$DEPENDS" ] && echo "Depends: $DEPENDS"
  echo "Section: $SECTION"
  echo "Priority: optional"
  echo "Description: $SUMMARY"
  echo "$DESCRIPTION" | fold -s -w 78 | sed 's/^/ /'
} > "$PKGROOT/DEBIAN/control"

dpkg-deb --build --root-owner-group "$PKGROOT" "$DEB" >/dev/null
rm -rf "$WORK"
echo "Built: $DEB"

# --- release folder for bundle / link -----------------------------------------
case "$PREREQ_MODE" in
  none|repo) dpkg-deb -I "$DEB" | sed -n '/Package:/,$p'; exit 0 ;;
  bundle|link) ;;
  *) die "unknown PREREQ_MODE $PREREQ_MODE" ;;
esac

REL="$OUT_DIR/release"
rm -rf "$REL"; mkdir -p "$REL"
cp "$DEB" "$REL/"
shavar="PREREQ_SHA256_$ARCH"; SHA="${!shavar:-}"
[ -n "$SHA" ] || die "$shavar is empty"
VENDOR_DEB=""
if [ "$PREREQ_MODE" = bundle ]; then
  vfile="${PREREQ_FILE//@ARCH@/$ARCH}"
  [ -f "$vfile" ] || die "missing $vfile (see installer/prereqs/README.md)"
  got="$(sha256sum "$vfile" | cut -d' ' -f1)"
  [ "$got" = "$SHA" ] || die "SHA-256 of $vfile is $got, expected $SHA"
  vpkg="$(dpkg-deb -f "$vfile" Package)"
  [ "$vpkg" = "$PREREQ_PACKAGE" ] || die "$vfile is package '$vpkg', expected '$PREREQ_PACKAGE'"
  VENDOR_DEB="$(basename "$vfile")"
  cp "$vfile" "$REL/"
fi
sed -e "s|@MODE@|$PREREQ_MODE|g" -e "s|@PACKAGE@|$PACKAGE|g" -e "s|@APP_DEB@|$DEB_NAME|g" \
    -e "s|@ARCH@|$ARCH|g" -e "s|@VENDOR_PACKAGE@|$PREREQ_PACKAGE|g" \
    -e "s|@VENDOR_MIN@|$PREREQ_MIN_VERSION|g" -e "s|@VENDOR_DEB@|$VENDOR_DEB|g" \
    -e "s|@VENDOR_URL@|${PREREQ_URL//@ARCH@/$ARCH}|g" -e "s|@VENDOR_SHA256@|$SHA|g" \
    "$HERE/install.sh.in" > "$REL/install.sh"
chmod 755 "$REL/install.sh"
(cd "$REL" && sha256sum ./*.deb > SHA256SUMS)

NAME="${PACKAGE}-${VERSION}-linux-${ARCH}"
if command -v makeself >/dev/null; then
  makeself --quiet --sha256 "$REL" "$OUT_DIR/$NAME.run" "$PACKAGE $VERSION" ./install.sh
  echo "Built: $OUT_DIR/$NAME.run   (users run: sh $NAME.run)"
else
  tar -C "$OUT_DIR" -czf "$OUT_DIR/$NAME.tar.gz" --transform "s|^release|$NAME|" release
  echo "Built: $OUT_DIR/$NAME.tar.gz (install makeself for a single .run file)"
fi
