#!/usr/bin/env bash
# Registers the yesem-pcm:// scheme for a development build of the Pin Code
# Manager, so the browser demo (tool/web_demo) works without installing.
# The installers do this themselves (macOS: Info.plist; Linux: .deb).
#
#   macOS:  tool/web_demo/register_scheme.sh ["path/to/YesEm Pin Code Manager.app"]
#   Linux:  tool/web_demo/register_scheme.sh [path/to/yesem-pincode]   (--unregister to undo)
set -euo pipefail
cd "$(dirname "$0")/../.."

case "$(uname -s)" in
  Darwin)
    APP="${1:-build/macos/Build/Products/Debug-pincode/YesEm Pin Code Manager.app}"
    [ -d "$APP" ] || { echo "Build it first: fvm flutter build macos --debug --flavor pincode" >&2; exit 1; }
    # macOS reads the scheme from the app's Info.plist; this just makes
    # LaunchServices (re)index this copy. With several copies (Debug, Release,
    # /Applications) macOS picks one of them; remove the others if links open
    # the wrong one.
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
    echo "Registered yesem-pcm:// for $APP"
    ;;
  Linux)
    ENTRY="$HOME/.local/share/applications/yesem-pcm-dev.desktop"
    if [ "${1:-}" = "--unregister" ]; then
      rm -f "$ENTRY"; update-desktop-database "$(dirname "$ENTRY")" 2>/dev/null || true
      echo "Removed $ENTRY"; exit 0
    fi
    EXE="${1:-}"
    if [ -z "$EXE" ]; then
      EXE="$(ls -d dist/linux/pincode/yesem-pincode build/linux/*/pincode/*/bundle/yesem 2>/dev/null | head -1 || true)"
    fi
    [ -x "$EXE" ] || { echo "Build it first: tool/build_desktop_bundles.sh (or pass the executable)" >&2; exit 1; }
    EXE="$(cd "$(dirname "$EXE")" && pwd)/$(basename "$EXE")"
    mkdir -p "$(dirname "$ENTRY")"
    cat > "$ENTRY" <<EOF
[Desktop Entry]
Type=Application
Name=YesEm Pin Code Manager (dev)
Exec="$EXE" --yesem-role=pincode %u
Terminal=false
NoDisplay=true
MimeType=x-scheme-handler/yesem-pcm;
EOF
    update-desktop-database "$(dirname "$ENTRY")" 2>/dev/null || true
    xdg-mime default "$(basename "$ENTRY")" x-scheme-handler/yesem-pcm
    echo "Registered yesem-pcm:// for $EXE ($(xdg-mime query default x-scheme-handler/yesem-pcm))"
    ;;
  *) echo "Windows: use tool\\web_demo\\register_scheme.ps1" >&2; exit 1 ;;
esac
