#!/usr/bin/env bash
#
# Set up hibernation + suspend-then-hibernate on this Fedora/Sway laptop.
#
# Why: firmware exposes no S3 deep sleep (ACPI reports S0 S4 S5 only), so a
# closed-lid "suspend" is really s2idle and keeps draining. This configures a
# real disk swapfile + S4 hibernation, and makes lid-close on battery do
# suspend-then-hibernate (instant s2idle for quick reopens, then auto-hibernate
# before the battery would run out).
#
# Safe to re-run: each step checks for prior state.
# Run as: sudo bash setup-hibernate.sh
set -euo pipefail

FSUUID="80952777-6e98-4931-85ee-283872037152"   # btrfs filesystem UUID (also root=)
SWAP_SUBVOL="/swap"
SWAPFILE="/swap/swapfile"
SWAP_SIZE="18g"                                  # >= 16G RAM, for the hibernation image

if [[ $EUID -ne 0 ]]; then echo "Run with sudo." >&2; exit 1; fi

echo "==> [1/7] Disk swapfile for hibernation"
if ! btrfs subvolume show "$SWAP_SUBVOL" &>/dev/null; then
  btrfs subvolume create "$SWAP_SUBVOL"
fi
if [[ ! -f "$SWAPFILE" ]]; then
  btrfs filesystem mkswapfile -s "$SWAP_SIZE" "$SWAPFILE"
  echo "    created $SWAPFILE ($SWAP_SIZE)"
else
  echo "    $SWAPFILE already exists, skipping creation"
fi
swapon --show=NAME --noheadings | grep -qx "$SWAPFILE" || swapon "$SWAPFILE"
# SELinux: btrfs subvolume create + mkswapfile leave /swap and the swapfile as
# unlabeled_t. Without swapfile_t, systemd-logind is denied read access to the
# swapfile and `systemctl hibernate` fails with "Access denied". The /swap dir
# itself only needs to be searchable, which its default label (default_t) gives.
if command -v semanage &>/dev/null; then
  semanage fcontext -l 2>/dev/null | grep -q "^$SWAPFILE .*swapfile_t" || \
    semanage fcontext -a -t swapfile_t "$SWAPFILE"
  restorecon -Rv "$SWAP_SUBVOL"
  echo "    labeled $SWAPFILE swapfile_t (SELinux)"
else
  echo "    WARNING: semanage missing (dnf install policycoreutils-python-utils);" >&2
  echo "             swapfile stays unlabeled -> hibernate will be SELinux-denied" >&2
fi

echo "==> [2/7] Persist swapfile in /etc/fstab (low priority; zram stays primary)"
if ! grep -q "^$SWAPFILE " /etc/fstab; then
  printf '%s none swap defaults,pri=-2 0 0\n' "$SWAPFILE" >> /etc/fstab
  echo "    added fstab entry"
else
  echo "    fstab entry already present"
fi

echo "==> [3/7] Compute resume_offset"
OFFSET="$(btrfs inspect-internal map-swapfile -r "$SWAPFILE")"
if ! [[ "$OFFSET" =~ ^[0-9]+$ ]]; then
  echo "    ERROR: could not read resume offset (got '$OFFSET'). Aborting before touching boot." >&2
  exit 1
fi
echo "    resume=UUID=$FSUUID  resume_offset=$OFFSET"

echo "==> [4/7] Add kernel cmdline (current entries + future kernels)"
grubby --update-kernel=ALL --remove-args="resume resume_offset" >/dev/null 2>&1 || true
grubby --update-kernel=ALL --args="resume=UUID=$FSUUID resume_offset=$OFFSET"
# Future kernels inherit from /etc/kernel/cmdline on this system:
if [[ -f /etc/kernel/cmdline ]]; then
  NEWCMD="$(sed -E 's/\bresume=[^ ]*//g; s/\bresume_offset=[^ ]*//g; s/ +/ /g; s/ +$//' /etc/kernel/cmdline)"
  printf '%s resume=UUID=%s resume_offset=%s\n' "$NEWCMD" "$FSUUID" "$OFFSET" > /etc/kernel/cmdline
  echo "    updated /etc/kernel/cmdline"
fi

echo "==> [5/7] Ensure initramfs can resume, then rebuild"
echo 'add_dracutmodules+=" resume "' > /etc/dracut.conf.d/resume.conf
dracut --regenerate-all --force
echo "    initramfs rebuilt"

echo "==> [6/7] systemd sleep + lid behaviour"
install -d /etc/systemd/sleep.conf.d /etc/systemd/logind.conf.d
cat > /etc/systemd/sleep.conf.d/10-hibernate.conf <<'EOF'
[Sleep]
# suspend-then-hibernate: stay in s2idle for quick reopens, then hibernate
# before the battery is estimated to deplete. Re-check the estimate every 30 min.
HibernateMode=platform shutdown
SuspendEstimationSec=30min
EOF
cat > /etc/systemd/logind.conf.d/10-lid.conf <<'EOF'
[Login]
HandleLidSwitch=suspend-then-hibernate
HandleLidSwitchExternalPower=suspend
HandleLidSwitchDocked=ignore
EOF
echo "    wrote sleep.conf.d and logind.conf.d drop-ins"

echo "==> [7/7] UPower low-battery backstop (clean hibernate, not a hard death)"
if [[ -f /etc/UPower/UPower.conf ]]; then
  sed -i -E 's/^[# ]*CriticalPowerAction=.*/CriticalPowerAction=Hibernate/' /etc/UPower/UPower.conf
  grep -q '^CriticalPowerAction=Hibernate' /etc/UPower/UPower.conf || \
    echo 'CriticalPowerAction=Hibernate' >> /etc/UPower/UPower.conf
  echo "    CriticalPowerAction=Hibernate"
fi

echo
echo "Done. Active swap:"; swapon --show
echo
echo "Verify cmdline was applied to the booted entry:"
grubby --info="$(grubby --default-kernel)" | grep -o 'resume=[^"]*' || true
echo
echo "NEXT: reboot (so the new cmdline + initramfs take effect), then test:"
echo "   sudo systemctl hibernate"
echo "Press the power button to wake; you should land back in your session."
