#!/usr/bin/env bash
# Removes what YesEm-<version>.pkg installed, so the installer can be tested
# again from a clean state. macOS installers have no built-in uninstaller:
# delete the apps and forget the package receipts.
#
# Usage: sudo tool/macos_installer/uninstall.sh
set -euo pipefail

rm -rf "/Applications/YesEm Desktop.app" "/Applications/YesEm Pin Code Manager.app"
for id in global.volo.yesem.desktop global.volo.yesem.pincode; do
  pkgutil --pkgs="$id" >/dev/null 2>&1 && pkgutil --forget "$id"
done
echo "YesEm removed."
