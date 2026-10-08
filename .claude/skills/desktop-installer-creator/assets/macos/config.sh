# macOS installer configuration, sourced by build.sh.
# Paths are relative to PROJECT_ROOT (default: two levels above this file).

PRODUCT_NAME="MyApp"                  # installer title and welcome page name
ORGANIZATION="com.example"
VERSION="1.0.0"                       # e.g. "$(grep -m1 '^version:' pubspec.yaml | sed -E 's/version:[[:space:]]*//; s/\+.*//')"
MIN_MACOS="12.0"
OUT_DIR="${OUT_DIR:-dist/macos}"           # environment may override
PKG_NAME="$PRODUCT_NAME-$VERSION.pkg"

# Release build, run before packaging unless build.sh --skip-build. Empty: none.
BUILD_COMMAND="flutter build macos --release"

# Apps installed into /Applications, one "path/to/App.app|bundle.id" per entry.
# Several apps (for example a main app and a helper) go into one installer.
APPS=(
  "build/macos/Build/Products/Release/MyApp.app|com.example.myapp"
)
ENTITLEMENTS=""                       # entitlements for codesign (release entitlements file), optional

# --- Prerequisite --------------------------------------------------------
# none | bundle | bundle-untouched | link
#   bundle            vendor package(s) become components of our installer
#   bundle-untouched  vendor's original .pkg shipped as is, run from postinstall
#   link              postinstall downloads PREREQ_URL, checks it, installs it
PREREQ_MODE="none"
PREREQ_NAME="Vendor Middleware"
PREREQ_FILE="${PREREQ_FILE:-installer/prereqs/VendorMiddleware.pkg}"   # bundle modes: .pkg, or .dmg containing a .pkg or .app
PREREQ_URL=""                                          # link mode: versioned URL of a .pkg
PREREQ_SHA256=""                                       # SHA-256 of PREREQ_FILE / of the file at PREREQ_URL
PREREQ_ID="com.vendor.middleware"                      # package id (pkgutil --pkgs) for detection;
                                                       # for a .app inside a .dmg: the id our wrapper package gets
PREREQ_VERSION="1.2.3"                                 # minimum version; newer installs are left alone
PREREQ_APP_PATH=""                                     # optional: "/Applications/Vendor.app" for version detection by bundle
PREREQ_TEAM_ID=""                                      # optional: vendor's Apple Team ID, checked on the .pkg signature

# Signing (environment, not this file): APP_SIGN_IDENTITY, PKG_SIGN_IDENTITY, NOTARY_PROFILE
