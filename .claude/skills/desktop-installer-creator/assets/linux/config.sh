# Debian/Ubuntu installer configuration, sourced by build.sh.
# Paths are relative to PROJECT_ROOT (default: two levels above this file).

PACKAGE="myapp"                        # Debian package name: lower case, permanent
VERSION="1.0.0-1"                      # upstream-revision, e.g. pubspec 1.0.0+1 -> 1.0.0-1
MAINTAINER="Example Ltd <support@example.com>"
SUMMARY="MyApp desktop application"    # one line
DESCRIPTION="MyApp does something useful. This paragraph appears in package managers."
SECTION="utils"
OUT_DIR="${OUT_DIR:-dist/linux}"           # environment may override
BUILD_COMMAND="flutter build linux --release"   # "" for none

INSTALL_ROOT="/opt/myapp"
# One "source dir|subdir under INSTALL_ROOT ('.' for the root)|executable" per app.
APPS=(
  "build/linux/x64/release/bundle|.|myapp"
)
# Commands in /usr/bin: "name|path under INSTALL_ROOT"
BIN_LINKS=(
  "myapp|myapp"
)
DESKTOP_FILE="installer/linux/com.example.myapp.desktop"   # launcher; "" for none
ICON_NAME="com.example.myapp"          # Icon= in the launcher
# PNG icons: "size|file". Sizes are installed under /usr/share/icons/hicolor/<size>x<size>/apps/
ICONS=(
  "256|assets/icon-256.png"
)
EXTRA_DEPENDS=""                       # added to the computed Depends, e.g. "pcscd"
COPYRIGHT_FILE=""                      # Debian copyright incl. third-party notices; "" writes a minimal one

# --- Prerequisite --------------------------------------------------------
# none | repo | bundle | link
#   repo    the prerequisite comes from a repository apt already knows (Ubuntu's or the vendor's);
#           only Depends is added
#   bundle  vendor .deb shipped next to ours: release folder + install.sh + self-extracting .run
#   link    install.sh downloads the vendor .deb (pinned SHA-256), then installs both
PREREQ_MODE="none"
PREREQ_PACKAGE="vendor-middleware"     # its Debian package name (dpkg-deb -f file.deb Package)
PREREQ_MIN_VERSION="1.2.3"
# @ARCH@ is replaced with amd64 / arm64
PREREQ_FILE="${PREREQ_FILE:-installer/prereqs/vendor-middleware_1.2.3_@ARCH@.deb}"    # bundle
PREREQ_URL="https://downloads.vendor.example/1.2.3/vendor-middleware_1.2.3_@ARCH@.deb"   # link
PREREQ_SHA256_amd64=""
PREREQ_SHA256_arm64=""
