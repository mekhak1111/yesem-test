# Testing on the Ubuntu VM (VMware Fusion)

State on 2026-09-15: the VM `Ubuntu 64-bit Arm 26.04.1.vmwarevm` runs with NAT
networking (guest seen at 192.168.80.131, may change), **no VMware Tools** and
**no SSH server**. Until one command is run inside the guest there is no way to
automate it from the Mac.

## 1. Once, inside the VM (terminal)

```sh
sudo apt install -y openssh-server open-vm-tools open-vm-tools-desktop
```

`openssh-server` lets the Mac push files and run the setup; `open-vm-tools`
gives clipboard sharing, display resizing and `vmrun` guest commands.

Optional, avoids ever sharing the password: passwordless sudo for your user and
the Mac's SSH key (paste it after Tools give you a shared clipboard):

```sh
echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/$USER
mkdir -p ~/.ssh && chmod 700 ~/.ssh && nano ~/.ssh/authorized_keys   # paste ~/.ssh/id_ed25519.pub from the Mac
```

## 2. From the Mac

```sh
tool/vm/ubuntu_from_mac.sh "$HOME/Desktop/Ubuntu 64-bit Arm 26.04.1.vmwarevm/Ubuntu 64-bit Arm 26.04.1.vmx" <guest-user>
```

It finds the guest IP from Fusion's DHCP leases, copies a clean project archive
plus `ubuntu_setup.sh` into the guest and runs it. That script installs the
Flutter Linux toolchain, FVM and the pinned Flutter 3.47.4, then runs
`flutter doctor`, the tests and the first `flutter build linux --flavor pincode`.
Everything it prints is also in `~/yesem_setup.log` in the guest.

## 3. Click-through test inside the VM

```sh
cd ~/yesem
export PATH="$HOME/fvm/bin:$PATH"   # the setup script also adds this to ~/.bashrc
fvm flutter run -d linux --flavor desktop
```

Expect the title "YesEm Desktop". Click Sign → a "YesEm Pin Code Manager"
window → type a PIN → Confirm → the PIN shows in Desktop. Then:

* fallback: `mv build/linux/arm64/pincode build/linux/arm64/pincode.off`, click
  Sign again, Desktop runs its own executable in helper role;
* Cancel, and closing the helper without a PIN, are reported by Desktop;
* `tool/build_desktop_bundles.sh` then `dist/linux/desktop/yesem-desktop`.

Blank window or GL errors (VM without 3D acceleration):
`LIBGL_ALWAYS_SOFTWARE=1 fvm flutter run -d linux --flavor desktop`.

## 4. Debian package (`.deb`)

Done on 2026-10-07 in the Ubuntu 26.04 arm64 VM. `tool/build_linux_installer.sh`
mirrors `tool/build_macos_installer.sh`; decisions, so they are not re-litigated:

* **One package `yesem`** with both apps, `/opt/yesem/desktop/yesem-desktop` and
  `/opt/yesem/pincode/yesem-pincode`, each with its own `lib/` and `data/`,
  copied from `tool/build_desktop_bundles.sh` output. `/opt` because the
  Flutter bundles are self-contained trees, not FHS-split files; lintian's
  `dir-or-file-in-opt` is overridden in `tool/linux_installer/lintian-overrides`.
* **No Dart change**: `PinCodeManagerLocator` already lists the sibling
  `pincode/` folder and `/opt/yesem/pincode/`. `/usr/bin/yesem-desktop` is a
  symlink; `Platform.resolvedExecutable` resolves it, so the helper is found
  when Desktop starts from the launcher, from `yesem-desktop` or by full path.
* **Application ids per flavor** on Linux: `linux/CMakeLists.txt` sets
  `APPLICATION_ID` to `global.volo.yesem.desktop` / `.pincode` from
  `FLUTTER_APP_FLAVOR` (available after `add_subdirectory(flutter)`). The
  launcher is `global.volo.yesem.desktop.desktop` with the same
  `StartupWMClass`, so GNOME pairs the Desktop window with its icon and does
  not group the helper window with it. Only Desktop has a launcher.
* **Icons**: the PNGs from `macos/Runner/Assets.xcassets/AppIcon.appiconset`
  (16 to 512 px) go to `/usr/share/icons/hicolor/<size>x<size>/apps/`.
  No maintainer scripts: dpkg triggers of `desktop-file-utils` and
  `hicolor-icon-theme` refresh the caches.
* **Version** `0.1.0+1` → `0.1.0-1`; `YESEM_DEB_VERSION` overrides it.
  **Architecture** from `dpkg --print-architecture` (arm64 here, amd64 on x64).
* **Depends** from `dpkg-shlibdeps` over the two runners and all bundled
  `.so` files, staged under `debian/yesem/` so the bundled engine and plugins
  count as the package's own libraries. Only missing-library/symbol warnings
  are shown (`--warnings=6`); Flutter over-links GTK and the rest is noise.
* **Unsigned**. Maintainer `Volo <support@volo.global>` (lintian requires an
  address; change it in `tool/linux_installer/control.in` if wrong).

Test plan (the `apt` steps need sudo):

```sh
tool/build_linux_installer.sh --skip-build          # after tool/build_desktop_bundles.sh
lintian dist/linux/yesem_*.deb                      # sudo apt install lintian
sudo apt install ./dist/linux/yesem_0.1.0-1_arm64.deb
# Activities → "YesEm Desktop" → Sign → PIN → shown in Desktop
sudo apt install ./dist/linux/yesem_0.1.0-1_arm64.deb   # reinstall same version
YESEM_DEB_VERSION=0.1.1-1 tool/build_linux_installer.sh --skip-build
sudo apt install ./dist/linux/yesem_0.1.1-1_arm64.deb   # upgrade: one copy, dpkg -l yesem
sudo apt remove yesem                               # /opt/yesem and the launcher gone
```

Driving the click-through without a mouse: with
`gsettings set org.gnome.desktop.interface toolkit-accessibility true` the
Flutter windows expose their widgets over AT-SPI (`python3-gi` with
`Atspi 2.0`), so the Sign/Confirm buttons and the PIN field can be scripted.
GNOME only gives the helper keyboard focus when it was opened from a focused
Desktop window; otherwise the PIN field ignores text.

## Notes

* Do not build in a VMware shared folder; keep the project on the guest disk.
* The Windows 11 ARM VM needs the same kind of foothold: OpenSSH Server
  (Settings → Optional features) or VMware Tools, plus Visual Studio 2022 with
  the C++ desktop workload and Developer Mode. Ask and the equivalent scripts
  can be added.

## Browser → Pin Code Manager link (yesem-pcm://)

See README "Browser → Pin Code Manager". In the VM:

```sh
git pull
tool/build_desktop_bundles.sh
tool/web_demo/register_scheme.sh
fvm dart run tool/web_demo/server.dart
```

Open http://127.0.0.1:8787 in the VM's browser, click **Sign with ID card**,
allow opening the Pin Code Manager, enter a PIN, Confirm: the page must show
"Done" and the PIN. Also check Cancel, and that a second click opens a new
Pin Code Manager window (no single-instance forwarding on Linux yet).
After installing the .deb, unregister the dev entry
(register_scheme.sh --unregister) and repeat: the installed app must handle the link.

