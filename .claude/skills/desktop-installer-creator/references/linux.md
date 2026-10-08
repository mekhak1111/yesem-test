# Ubuntu / Debian installer (.deb, .run)

## Contents
1. Why there's no "installer inside the installer"
2. Using assets/linux/build.sh
3. Prerequisite modes
4. Manual equivalent (no script)
5. Verify and install
6. APT repository and pitfalls

## 1. Why there's no "installer inside the installer"

While a `.deb` installs, dpkg holds the package database lock, so our
package's maintainer scripts can't run `dpkg -i`/`apt install` for the vendor
package (it would block or fail with "Could not get lock"). Instead:

- our package declares `Depends: vendor-middleware (>= 1.2.3)`;
- **apt installs both in one transaction** when both are available: from a
  repository, or as local files on the same command line
  (`apt-get install ./vendor.deb ./myapp.deb`).

The bundle equivalent of a Windows setup.exe is therefore a **self-extracting
`.run`** (makeself) or a release archive containing both `.deb` files and an
`install.sh`. Merging the vendor's files into our `.deb` is possible only with
permission, conflicts with their own package (`Conflicts`/`Replaces`), and
skips their maintainer scripts (services, udev rules); avoid it. Background
installs triggered from `postinst` (systemd-run, at) are fragile and invisible
to apt; don't use them.

## 2. Using assets/linux/build.sh

Copy `assets/linux/{build.sh,config.sh,install.sh.in}` to `installer/linux/`
and `assets/linux/app.desktop` to `installer/linux/<app-id>.desktop`; fill in
both. Requirements on the build machine: `sudo apt install dpkg-dev binutils file`,
optionally `makeself lintian`. Build on the target architecture
(`dpkg --print-architecture`) and on the oldest Ubuntu release you support,
because computed library dependencies follow the build machine.

```sh
installer/linux/build.sh              # build + package
installer/linux/build.sh --skip-build
```

Steps: run the build, stage apps under `INSTALL_ROOT` (default `/opt/<pkg>`;
self-contained bundles like Flutter's belong in /opt), strip symbols, add
`/usr/bin` symlinks, launcher and icons, compute `Depends` with
`dpkg-shlibdeps` (plus the prerequisite and `EXTRA_DEPENDS`), write
`DEBIAN/control`, `dpkg-deb --build --root-owner-group`. With `bundle`/`link`
it also writes `dist/linux/release/` (our .deb, vendor .deb for bundle,
`install.sh`, `SHA256SUMS`) and `<pkg>-<version>-linux-<arch>.run`
(or `.tar.gz` without makeself).

Version: Debian format `upstream-revision`, e.g. `1.0.0-1`. Flutter's
`1.0.0+1` maps to `1.0.0-1`.

## 3. Prerequisite modes

| `PREREQ_MODE` | Ship | User runs | Notes |
|---|---|---|---|
| `none` | `.deb` | `sudo apt install ./myapp_….deb` | |
| `repo` | `.deb` | add the vendor's repository once (if not Ubuntu's), then `sudo apt install ./myapp_….deb` | cleanest; updates via `apt upgrade` |
| `bundle` | `.run` (or release folder) | `sh myapp-1.0.0-1-linux-amd64.run` | build checks vendor SHA-256 and package name |
| `link` | `.run` / release folder without the vendor .deb | same | `install.sh` downloads the pinned URL, checks SHA-256 |

`install.sh` skips the vendor package when the same or a newer version is
installed (apt refuses local downgrades anyway), installs everything in one
`apt-get install -y`, and runs `apt-mark manual` so `apt autoremove` keeps the
vendor package after our app is removed.

Vendor's APT repository (users, once):

```sh
sudo install -d /etc/apt/keyrings
curl -fsSL https://apt.vendor.example/key.asc | sudo gpg --dearmor -o /etc/apt/keyrings/vendor.gpg
echo "deb [signed-by=/etc/apt/keyrings/vendor.gpg] https://apt.vendor.example stable main" |
  sudo tee /etc/apt/sources.list.d/vendor.list
sudo apt update
```

## 4. Manual equivalent (no script)

```
pkg/
├── DEBIAN/control
├── opt/myapp/…                        # app bundle
├── usr/bin/myapp -> /opt/myapp/myapp
├── usr/share/applications/com.example.myapp.desktop
└── usr/share/icons/hicolor/256x256/apps/com.example.myapp.png
```

```
Package: myapp
Version: 1.0.0-1
Architecture: amd64
Maintainer: Example Ltd <support@example.com>
Depends: vendor-middleware (>= 1.2.3), libgtk-3-0t64
Section: utils
Priority: optional
Description: MyApp desktop application
 Longer description, each line starting with a space.
```

```sh
find pkg -type d -exec chmod 755 {} +
dpkg-deb --build --root-owner-group pkg dist/myapp_1.0.0-1_amd64.deb
mkdir release && cp dist/myapp_1.0.0-1_amd64.deb vendor-middleware_1.2.3_amd64.deb install.sh release/
(cd release && sha256sum ./*.deb > SHA256SUMS)
makeself --sha256 release/ dist/MyApp-1.0.0-linux-amd64.run "MyApp 1.0.0" ./install.sh
```

## 5. Verify and install

```sh
dpkg-deb -I dist/linux/myapp_1.0.0-1_amd64.deb      # control fields, Depends
dpkg-deb -c dist/linux/myapp_1.0.0-1_amd64.deb | head
lintian dist/linux/myapp_1.0.0-1_amd64.deb          # dir-or-file-in-opt is expected for /opt
sh dist/linux/myapp-1.0.0-1-linux-amd64.run --check   # makeself archive integrity
# the user runs (sudo):
sh dist/linux/myapp-1.0.0-1-linux-amd64.run          # or: sudo apt install ./dist/linux/myapp_….deb
dpkg -l myapp vendor-middleware
sudo apt remove myapp                                 # vendor stays
```

## 6. APT repository and pitfalls

- Own repository (updates through `apt upgrade`): GPG key
  (`gpg --full-generate-key`), `reprepro` with `SignWith: <keyid>` in
  `conf/distributions`, `reprepro -b repo includedeb stable myapp_….deb`, host
  `dists/`, `pool/` and the public key over HTTPS. See `signing.md`.
- Launchers: `StartupWMClass` must equal the window's application id (GTK
  apps: the `APPLICATION_ID`), otherwise the dock shows a generic icon. If one
  product ships several GTK apps, give each its own id.
- `/usr/bin` symlinks are fine for apps that resolve their own location via
  `/proc/self/exe` (Flutter does).
- Snap/Flatpak are sandboxed and generally can't install system-level
  middleware or drivers for the user; they're a poor fit for prerequisites.
