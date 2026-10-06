#!/usr/bin/env bash
# Bootstraps an Ubuntu (24.04+/26.04, x64 or arm64) machine for this project
# and runs the first real Linux build. Idempotent; safe to re-run.
#
#   bash ubuntu_setup.sh [/path/to/yesem.tgz]
#
# Steps: apt packages for Flutter Linux desktop → FVM → unpack the project into
# ~/yesem → pinned Flutter SDK (.fvmrc) → doctor, tests, helper flavor build.
# `sudo` may prompt for your password; set SUDO_PASSWORD to run unattended.
set -euo pipefail

ARCHIVE="${1:-$HOME/yesem.tgz}"
PROJECT="${PROJECT_DIR:-$HOME/yesem}"
LOG="$HOME/yesem_setup.log"
exec > >(tee -a "$LOG") 2>&1

# Two copies racing each other corrupt the FVM install; allow one at a time.
exec 9>"$HOME/.yesem_setup.lock"
if ! flock -n 9; then
  echo "Another ubuntu_setup.sh is already running; wait for it to finish." >&2
  exit 1
fi
echo "== $(date) : YesEm Ubuntu setup starting (archive: $ARCHIVE, project: $PROJECT) =="

sudo_() {
  if [ -n "${SUDO_PASSWORD:-}" ]; then
    printf '%s\n' "$SUDO_PASSWORD" | sudo -S -p '' "$@"
  else
    sudo "$@"
  fi
}

echo "== apt packages =="
export DEBIAN_FRONTEND=noninteractive
sudo_ apt-get update -y
# Flutter's documented Linux prerequisites plus build-essential, which brings
# the libstdc++ headers for whatever GCC this Ubuntu ships.
sudo_ apt-get install -y curl git unzip xz-utils zip clang cmake ninja-build \
  pkg-config libgtk-3-dev liblzma-dev build-essential openssh-server mesa-utils
sudo_ systemctl enable --now ssh

echo "== FVM =="
# The FVM installer has used different locations over time (~/fvm/bin since
# 4.x, ~/.fvm_flutter/bin before); put every known one on PATH.
add_fvm_paths() {
  local dir
  for dir in "$HOME/fvm/bin" "$HOME/.fvm_flutter/bin" "$HOME/.pub-cache/bin"; do
    if [ -d "$dir" ]; then
      case ":$PATH:" in
        *":$dir:"*) ;;
        *) export PATH="$dir:$PATH" ;;
      esac
    fi
  done
  return 0  # never let a missing directory trip `set -e`
}
add_fvm_paths
if ! command -v fvm >/dev/null 2>&1; then
  curl -fsSL https://fvm.app/install.sh | bash
  add_fvm_paths
fi
command -v fvm >/dev/null 2>&1 || { echo "fvm still not on PATH; installer output above shows where it went" >&2; exit 1; }
fvm --version
# Make fvm available in future terminals too.
FVM_BIN_DIR="$(dirname "$(command -v fvm)")"
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [ -f "$rc" ] && ! grep -qs "$FVM_BIN_DIR" "$rc"; then
    printf '\n# FVM (Flutter version manager)\nexport PATH="%s:$PATH"\n' "$FVM_BIN_DIR" >> "$rc"
  fi
done

echo "== project =="
if [ -f "$ARCHIVE" ]; then
  mkdir -p "$PROJECT"
  tar -xzf "$ARCHIVE" -C "$PROJECT"
  echo "unpacked $ARCHIVE into $PROJECT"
elif [ ! -f "$PROJECT/pubspec.yaml" ]; then
  echo "No archive at $ARCHIVE and no project at $PROJECT" >&2
  exit 1
fi
cd "$PROJECT"

FLUTTER_VERSION="$(tr -d '\n ' < .fvmrc | sed -E 's/.*"flutter" *: *"([^"]+)".*/\1/')"
echo "== Flutter $FLUTTER_VERSION via FVM =="
# A clone interrupted by Ctrl+C or by a second FVM process leaves a directory
# FVM will not reuse or delete; clear it before installing.
VERSION_DIR="$HOME/fvm/versions/$FLUTTER_VERSION"
if [ -d "$VERSION_DIR" ] && [ ! -x "$VERSION_DIR/bin/flutter" ]; then
  echo "Removing partial Flutter clone at $VERSION_DIR"
  rm -rf "$VERSION_DIR"
fi
fvm install
fvm flutter --suppress-analytics config --no-analytics >/dev/null 2>&1 || true
fvm flutter --version
fvm flutter doctor -v || true   # Android/Chrome lines are expected to be red

echo "== pub get / analyze / test =="
fvm flutter pub get
fvm flutter analyze
fvm flutter test

echo "== first Linux build: helper flavor =="
fvm flutter build linux --debug --flavor pincode
ls -la build/linux/*/pincode/debug/bundle/

echo "== $(date) : setup finished OK =="
echo "Next (new terminal, or: export PATH=\"$FVM_BIN_DIR:\$PATH\"):"
echo "  cd $PROJECT && fvm flutter run -d linux --flavor desktop"
