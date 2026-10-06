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

## Notes

* Do not build in a VMware shared folder; keep the project on the guest disk.
* The Windows 11 ARM VM needs the same kind of foothold: OpenSSH Server
  (Settings → Optional features) or VMware Tools, plus Visual Studio 2022 with
  the C++ desktop workload and Developer Mode. Ask and the equivalent scripts
  can be added.
