#!/usr/bin/env bash
# Host side (macOS + VMware Fusion): pushes this project into the Ubuntu VM and
# runs tool/vm/ubuntu_setup.sh there over SSH.
#
#   tool/vm/ubuntu_from_mac.sh <path/to/vm.vmx> <guest-user> [guest-ip]
#
# One-time prerequisite inside the guest:
#   sudo apt install -y openssh-server open-vm-tools open-vm-tools-desktop
#
# SSH uses your key if the guest has it in ~/.ssh/authorized_keys, otherwise
# it asks for the password. sudo inside the guest prompts too, unless you
# export SUDO_PASSWORD (avoid a single quote in it) or the guest user has
# NOPASSWD sudo.
set -euo pipefail
VMX="${1:?usage: $0 <vm.vmx> <guest-user> [guest-ip]}"
GUEST_USER="${2:?usage: $0 <vm.vmx> <guest-user> [guest-ip]}"
GUEST_IP="${3:-}"
cd "$(dirname "$0")/../.."

# The guest IP comes from Fusion's NAT DHCP leases, matched by the VM's MAC.
if [ -z "$GUEST_IP" ]; then
  MAC="$(grep -i 'ethernet0.generatedAddress ' "$VMX" | sed 's/.*= *"\(.*\)"/\1/' | tr 'A-F' 'a-f')"
  GUEST_IP="$(awk -v mac="$MAC" 'BEGIN{RS="}"} tolower($0) ~ mac {for(i=1;i<=NF;i++) if($i=="lease") ip=$(i+1)} END{print ip}' \
    /var/db/vmware/vmnet-dhcpd-vmnet8.leases 2>/dev/null || true)"
fi
[ -n "$GUEST_IP" ] || { echo "Could not determine the guest IP; pass it as the 3rd argument." >&2; exit 1; }
echo "Guest: $GUEST_USER@$GUEST_IP"

if ! nc -z -w 3 "$GUEST_IP" 22; then
  echo "SSH port 22 is closed on $GUEST_IP." >&2
  echo "Inside the VM run: sudo apt install -y openssh-server open-vm-tools open-vm-tools-desktop" >&2
  exit 1
fi

ARCHIVE="$(mktemp -d)/yesem.tgz"
tar --exclude='./build' --exclude='./dist' --exclude='./.dart_tool' --exclude='./.fvm' \
    --exclude='./.idea' --exclude='*.iml' --exclude='ephemeral' --exclude='./.claude' \
    -czf "$ARCHIVE" .
echo "Project archive: $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1))"

SSH_OPTS=(-o StrictHostKeyChecking=accept-new)
scp "${SSH_OPTS[@]}" "$ARCHIVE" tool/vm/ubuntu_setup.sh "$GUEST_USER@$GUEST_IP:~/"
ssh "${SSH_OPTS[@]}" -t "$GUEST_USER@$GUEST_IP" \
  "SUDO_PASSWORD='${SUDO_PASSWORD:-}' bash ~/ubuntu_setup.sh ~/yesem.tgz"
