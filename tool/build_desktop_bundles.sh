#!/usr/bin/env bash
# Builds YesEm Desktop and the YesEm Pin Code Manager for Linux and lays them
# out as two sibling applications:
#
#   dist/linux/desktop/yesem-desktop
#   dist/linux/pincode/yesem-pincode
#
# Desktop looks for the helper in the sibling pincode/ folder, so ship the two
# folders together. Run on Ubuntu with the Flutter Linux toolchain installed
# (clang, cmake, ninja-build, pkg-config, libgtk-3-dev).
#
# With Flutter 3.47 or newer the roles are real flavors (`--flavor`); older
# SDKs get the same result through `--dart-define=YESEM_APP=<role>`.
#
# Usage: tool/build_desktop_bundles.sh [release|debug|profile]
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-release}"
# Use the SDK pinned in .fvmrc when FVM is installed; otherwise whatever
# `flutter` is on PATH.
FLUTTER="flutter"
if command -v fvm >/dev/null 2>&1 && [ -f .fvmrc ]; then
  FLUTTER="fvm flutter"
fi
case "$(uname -m)" in
  x86_64) ARCH=x64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
OUT="dist/linux"

# Flavors on Linux need Flutter >= 3.47.
VERSION="$($FLUTTER --version 2>/dev/null | grep -m1 -o 'Flutter [0-9]*\.[0-9]*' | cut -d' ' -f2)"
MAJOR="${VERSION%%.*}"; MINOR="${VERSION#*.}"
if [ "${MAJOR:-0}" -gt 3 ] || { [ "${MAJOR:-0}" -eq 3 ] && [ "${MINOR:-0}" -ge 47 ]; }; then
  USE_FLAVORS=1; echo "Flutter $VERSION: building with --flavor"
else
  USE_FLAVORS=0; echo "Flutter $VERSION: no Linux flavors before 3.47, using --dart-define=YESEM_APP"
fi

build_role() {
  local role="$1" exe="$2" bundle
  echo "== Building $role ($MODE) =="
  if [ "$USE_FLAVORS" = 1 ]; then
    $FLUTTER build linux "--$MODE" --flavor "$role"
    bundle="build/linux/$ARCH/$role/$MODE/bundle"
  else
    $FLUTTER build linux "--$MODE" "--dart-define=YESEM_APP=$role"
    bundle="build/linux/$ARCH/$MODE/bundle"
  fi
  rm -rf "$OUT/$role"
  mkdir -p "$OUT/$role"
  cp -R "$bundle/." "$OUT/$role/"
  mv "$OUT/$role/yesem" "$OUT/$role/$exe"
}

build_role desktop yesem-desktop
build_role pincode yesem-pincode
echo "Done: $OUT/desktop/yesem-desktop and $OUT/pincode/yesem-pincode"
