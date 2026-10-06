#!/usr/bin/env bash
# Inside the Ubuntu VM: copy the latest project files from the VMware share
# into the local build copy (~/yesem). Only changed files are transferred;
# build output and machine-specific folders on either side are left alone.
#
#   bash ~/yesem/tool/vm/sync_from_share.sh          # once
#   bash ~/yesem/tool/vm/sync_from_share.sh --watch  # every 2 s until Ctrl+C
#
# After a sync, press `r` in a running `fvm flutter run` for a hot reload of
# Dart changes; changes under linux/ or to pubspec.yaml need a restart.
set -euo pipefail
SHARE="${SHARE:-/mnt/hgfs/testFlutterMObileDesktop}"
DEST="${DEST:-$HOME/yesem}"
[ -f "$SHARE/pubspec.yaml" ] || { echo "Share not mounted at $SHARE (see tool/vm/UBUNTU_VM.md)" >&2; exit 1; }

sync_once() {
  rsync -a --delete --itemize-changes \
    --exclude build --exclude .dart_tool --exclude .fvm --exclude dist \
    --exclude ephemeral --exclude .idea --exclude .claude --exclude '*.iml' \
    "$SHARE/" "$DEST/" | grep -v '^\.d\.\.t' || true
}

if [ "${1:-}" = "--watch" ]; then
  echo "Watching $SHARE → $DEST (Ctrl+C to stop)"
  while true; do sync_once; sleep 2; done
else
  sync_once
  echo "Synced $SHARE → $DEST"
fi
