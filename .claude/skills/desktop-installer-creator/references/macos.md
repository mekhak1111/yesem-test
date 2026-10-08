# macOS installer (.pkg)

## Contents
1. How a .pkg is structured
2. Using assets/macos/build.sh
3. Prerequisite modes in detail
4. Manual equivalent (no script)
5. Verify and install
6. Pitfalls

## 1. How a .pkg is structured

A distributable installer is a **product archive**: one or more **component
packages** (each installs a payload to a location, optionally with
`preinstall`/`postinstall` scripts) plus a `Distribution` XML that defines the
title, welcome/conclusion pages, allowed macOS versions, and which components
install in which order and under which conditions (JavaScript).

Tools (built into macOS / Xcode CLT): `pkgbuild` (component), `productbuild`
(product archive), `productsign`, `pkgutil` (expand/flatten/inspect),
`codesign`, `xcrun notarytool`, `xcrun stapler`, `spctl`.

## 2. Using assets/macos/build.sh

Copy `assets/macos/{build.sh,config.sh,resources/}` to `installer/macos/`
(or set `PROJECT_ROOT` / `CONFIG` when placing it elsewhere), fill in
`config.sh`, then:

```sh
installer/macos/build.sh                  # runs BUILD_COMMAND, then packages
installer/macos/build.sh --skip-build     # reuse the existing .app builds

APP_SIGN_IDENTITY="Developer ID Application: Example Ltd (TEAMID)" \
PKG_SIGN_IDENTITY="Developer ID Installer: Example Ltd (TEAMID)" \
NOTARY_PROFILE=my-notary installer/macos/build.sh
```

What it does: verifies the prerequisite (SHA-256, vendor signature/team),
signs each app inside-out with hardened runtime + timestamp (when
`APP_SIGN_IDENTITY` is set), builds one non-relocatable component per app,
prepares the vendor component(s) or the `postinstall`, generates
`distribution.xml` (kept as `dist/macos/distribution.xml` for review), runs
`productbuild` (signed when `PKG_SIGN_IDENTITY` is set), then notarizes and
staples (when `NOTARY_PROFILE` is set).

Several apps (main app + helpers) are several `APPS` entries; they share one
installer and one "app" choice. `ENTITLEMENTS` should be the release
entitlements file (no `get-task-allow`, no JIT unless needed).

## 3. Prerequisite modes in detail

| `PREREQ_MODE` | Vendor file | What ends up in our .pkg | Detection |
|---|---|---|---|
| `bundle` | product archive `.pkg` | vendor components, flattened, in the order of the vendor's Distribution | Distribution JS: receipt `/var/db/receipts/<PREREQ_ID>.plist` `PackageVersion`, or bundle version at `PREREQ_APP_PATH` |
| `bundle` | component `.pkg` | the component as is | same |
| `bundle` | `.dmg` with `.app` | our own component wrapping the unchanged `.app` (id `PREREQ_ID`) | same |
| `bundle-untouched` | `.pkg` (or `.dmg` with a `.pkg`) | original vendor `.pkg` + `postinstall` on our first component, runs `installer -pkg` | `pkgutil --pkg-info` in the script |
| `link` | URL of a `.pkg` | `postinstall` that downloads, checks SHA-256 (+ team), runs `installer -pkg` | `pkgutil --pkg-info` in the script |

Choosing between the two bundle modes:
- `bundle` is the cleanest Installer experience (one transaction, vendor shown in
  Installer's log, no nested install). Flattening a vendor **product archive**
  replaces the vendor's package signature with ours (their binaries keep their
  code signatures). Get the vendor's consent for that.
- `bundle-untouched` keeps the vendor's signed package byte-for-byte. Running
  `installer` from inside a `postinstall` works in practice but isn't documented
  by Apple: test on every supported macOS version. A non-zero exit fails the
  whole install.
- `link` has the same nested-install caveat plus the network ones.

Flattening also drops the vendor's own `Distribution` logic: their OS-version
and architecture checks and any `installation-check` script no longer run (the
component scripts inside their packages still do). The build prints the path of
their expanded `Distribution`; read it, and copy essential checks into ours or
use `bundle-untouched`.

Notarization scans everything inside our package, including vendor content.
If the vendor's binaries aren't Developer ID signed with hardened runtime,
notarization fails in `bundle` mode; ask the vendor for a notarized build or
fall back to `bundle-untouched` with their notarized `.pkg`.

Intel-only vendor software runs on Apple Silicon through Rosetta; mention it
on the welcome page if relevant. Keep `hostArchitectures="arm64,x86_64"`.

## 4. Manual equivalent (no script)

```sh
# sign the app (inside out)
ID="Developer ID Application: Example Ltd (TEAMID)"
find build/MyApp.app/Contents/Frameworks -depth \( -name '*.framework' -o -name '*.dylib' \) \
  -exec codesign --force --timestamp --options runtime --sign "$ID" {} \;
codesign --force --timestamp --options runtime --entitlements Release.entitlements --sign "$ID" build/MyApp.app

# component, non-relocatable
mkdir -p work/root && ditto --noextattr --noqtn build/MyApp.app work/root/MyApp.app
pkgbuild --analyze --root work/root work/myapp.plist
plutil -replace 0.BundleIsRelocatable -bool NO work/myapp.plist
pkgbuild --root work/root --component-plist work/myapp.plist --identifier com.example.myapp \
  --version 1.0.0 --install-location /Applications work/myapp.pkg

# vendor product archive -> component(s)
xar -tf VendorMiddleware.pkg | head                 # "Distribution" listed => product archive
pkgutil --expand VendorMiddleware.pkg work/vx
grep -oE '>#[^<]+<' work/vx/Distribution            # component order
pkgutil --flatten work/vx/Middleware.pkg work/vendor-1.pkg
grep -o '<pkg-info[^>]*>' work/vx/Middleware.pkg/PackageInfo   # identifier + version
```

Distribution (vendor first, skipped when the same or newer version exists):

```xml
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>MyApp</title>
    <welcome file="welcome.html" mime-type="text/html"/>
    <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
    <domains enable_localSystem="true" enable_currentUserHome="false" enable_anywhere="false"/>
    <volume-check><allowed-os-versions><os-version min="12.0"/></allowed-os-versions></volume-check>
    <script><![CDATA[
    function vendorNeeded() {
        var r = system.files.plistAtPath('/var/db/receipts/com.vendor.middleware.plist');
        var have = r ? r.PackageVersion : null;
        return !have || system.compareVersions(have, '1.2.3') < 0;
    }
    ]]></script>
    <choices-outline><line choice="vendor"/><line choice="app"/></choices-outline>
    <choice id="vendor" title="Vendor Middleware" start_selected="vendorNeeded()">
        <pkg-ref id="com.vendor.middleware"/>
    </choice>
    <choice id="app" title="MyApp"><pkg-ref id="com.example.myapp"/></choice>
    <pkg-ref id="com.vendor.middleware" version="1.2.3">vendor-1.pkg</pkg-ref>
    <pkg-ref id="com.example.myapp" version="1.0.0">myapp.pkg</pkg-ref>
</installer-gui-script>
```

```sh
productbuild --distribution distribution.xml --resources resources --package-path work \
  --version 1.0.0 --sign "Developer ID Installer: Example Ltd (TEAMID)" --timestamp dist/MyApp-1.0.0.pkg
xcrun notarytool submit dist/MyApp-1.0.0.pkg --keychain-profile my-notary --wait
xcrun stapler staple dist/MyApp-1.0.0.pkg
```

## 5. Verify and install

```sh
pkgutil --check-signature dist/MyApp-1.0.0.pkg       # signer chain, notarization
spctl -a -vv -t install dist/MyApp-1.0.0.pkg         # accepted, source=Notarized Developer ID
xcrun stapler validate dist/MyApp-1.0.0.pkg
pkgutil --expand dist/MyApp-1.0.0.pkg /tmp/x && ls /tmp/x && cat /tmp/x/Distribution
pkgutil --payload-files dist/MyApp-1.0.0.pkg | head
codesign -dv --verbose=2 dist/macos/apps/MyApp.app 2>&1 | grep -E 'Authority|flags|Timestamp'

sudo installer -pkg dist/MyApp-1.0.0.pkg -target / -verbose     # user runs this (admin)
pkgutil --pkgs | grep -E 'com.example|com.vendor'
```

Uninstall for retesting (macOS has no uninstaller): delete the apps from
`/Applications` and `sudo pkgutil --forget <id>` for our ids. Don't remove the
vendor's software unless testing the clean-machine case on a VM snapshot.

## 6. Pitfalls

- **Relocation**: without `BundleIsRelocatable = NO`, Installer updates any copy
  with the same bundle id it finds (e.g. in `build/`) instead of `/Applications`.
- **Extended attributes**: copy with `ditto --noextattr --noqtn` into the
  package root, or `._*` files end up in the payload.
- **Unsigned** builds install on the building Mac (no quarantine flag) but a
  downloaded copy is blocked elsewhere. Notarization requires both Developer ID
  certificates.
- **Running app during update**: add `<must-close><app id="com.example.myapp"/></must-close>`
  inside the app's `pkg-ref` in the Distribution to make Installer ask to quit it.
- Keep bundle ids and package ids stable across releases; raise
  `CFBundleVersion` every release.
