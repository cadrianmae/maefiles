#!/usr/bin/env bash
# Step 3: hibernation, on a reserved swapfile that everyday paging cannot touch.
#
#   /swap/swapfile   24G   pri=10,  in fstab, always on   <- everyday paging
#   /swap/hiberfile  20G   pri=100, NOT in fstab          <- reserved, always 100% free
#
# WHY TWO FILES. A single shared file cannot guarantee hibernation: everyday
# swap expands to fill whatever it is given, so on a long uptime the free space
# left in it may be smaller than the image. Making it bigger lowers the odds of
# failure but never removes them. Reserving a file that is OFF during normal
# operation is the only arrangement where the space is guaranteed to be there.
#
# WHY pri=100. systemd's find_hibernate_location() picks "the swap with highest
# priority (or largest amount of usable space, if priorities are equal)" and,
# per systemd#20761, does NOT fall back to a larger lower-priority swap. At the
# default negative priority the reserved file would be ignored in favour of the
# always-on pri=10 one. It must outrank it.
#
# WHY 20G FOR 15Gi OF RAM. The kernel writes a compressed image capped at 2/5 of
# RAM by default -- but any memory in use beyond that cap is swapped out FIRST,
# before the snapshot. So the space required tracks memory in use, not the image
# cap. Hence the usual rule: reserved space >= RAM, plus margin. If this machine
# ever gets 32GB, this file must grow to ~32G+; that is a two-minute recreate,
# with no resume_offset to recompute.
#
# NO resume= / resume_offset= ANYWHERE. systemd 259 on UEFI records the location
# in the HibernateLocation EFI variable at hibernate time and reads it back on
# boot. That removes the single most fragile part of the old setup -- the offset
# that had to be recomputed by hand every time the file was recreated, and whose
# failure mode was "hibernate appears to work, resume boots fresh".
#
# Run with sudo.

set -euo pipefail

SWAPDIR=/swap
SWAPFILE=$SWAPDIR/swapfile          # everyday, already built by 01-swap-zswap.sh
HIBERFILE=$SWAPDIR/hiberfile        # reserved
HIBERSIZE=20G
HIBERPRIO=100

(( EUID == 0 )) || { echo "run with sudo" >&2; exit 1; }

say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

say "current state"
swapon --show
free -h | head -2

[[ -d $SWAPDIR ]] || { echo "$SWAPDIR missing -- run 01-swap-zswap.sh first" >&2; exit 1; }

say "reserved hibernation file ($HIBERSIZE)"
if [[ -f $HIBERFILE ]]; then
    echo "$HIBERFILE already exists, leaving it"
else
    # /swap already has NOCOW set on the directory, so a file created here
    # inherits it. A swapfile that is not NOCOW, or that gets snapshotted,
    # corrupts.
    mkswap --file --size "$HIBERSIZE" -L HIBERFILE "$HIBERFILE"
    chmod 600 "$HIBERFILE"
fi
# SELinux is Enforcing. Without swapfile_t the swapon fails with a permission
# error that never mentions SELinux.
#
# 01-swap-zswap.sh registers the fcontext rule for /swap. Without that rule a
# bare restorecon relabels swapfile_t -> default_t, undoing what mkswap got
# right -- so verify the rule exists rather than relabelling blindly.
if semanage fcontext -l 2>/dev/null | grep -q "^${SWAPDIR}(/\.\*)?"; then
    restorecon -v "$HIBERFILE" || true
else
    echo "WARN: no swapfile_t fcontext rule for $SWAPDIR -- skipping restorecon." >&2
    echo "      Fix with: semanage fcontext -a -t swapfile_t \"${SWAPDIR}(/.*)?\"" >&2
fi
ls -Z "$HIBERFILE"
lsattr "$HIBERFILE" || true

# Deliberately NOT added to /etc/fstab and NOT activated now. Its whole purpose
# is to stay empty until the moment of hibernation.
say "fstab check -- hiberfile must NOT be listed"
if grep -qF "$HIBERFILE" /etc/fstab; then
    echo "ERROR: $HIBERFILE is in /etc/fstab. That defeats the reservation --" >&2
    echo "everyday paging would consume it. Remove that line." >&2
    exit 1
fi
grep -F "$SWAPFILE" /etc/fstab || { echo "$SWAPFILE missing from fstab" >&2; exit 1; }
echo "ok"

say "units"
install -o root -g root -m 0644 /dev/stdin \
    /etc/systemd/system/hibernate-preparation.service <<EOF
[Unit]
Description=Activate the reserved hibernation swapfile
Documentation=file://$HIBERFILE
Before=systemd-hibernate.service systemd-suspend-then-hibernate.service

[Service]
Type=oneshot
RemainAfterExit=no
# -p $HIBERPRIO is load-bearing: systemd selects the highest-priority swap and
# will not fall back to a larger one at lower priority. Without this the 24G
# everyday file is chosen and the reservation is pointless.
ExecStart=/usr/sbin/swapon -p $HIBERPRIO $HIBERFILE

[Install]
WantedBy=systemd-hibernate.service systemd-suspend-then-hibernate.service
EOF

install -o root -g root -m 0644 /dev/stdin \
    /etc/systemd/system/hibernate-resume.service <<EOF
[Unit]
Description=Deactivate the reserved hibernation swapfile after resume
After=hibernate.target

[Service]
Type=oneshot
# Failing here is not fatal -- it only means the reserved file stays active as
# ordinary swap until the next boot.
ExecStart=/usr/sbin/swapoff $HIBERFILE

# Clearing the resume pointer is NOT optional, and its absence is subtle: the
# first hibernate of a boot succeeds, and every one after it fails with
#   "Specified resume device is missing or is not an active swap device"
# until reboot. systemd writes /sys/power/resume when it hibernates, pointing at
# whichever swap it chose -- the reserve. Swapping that file off above leaves the
# kernel pointing at a device that is no longer active swap, and systemd
# validates that pointer before every subsequent hibernate call.
# Observed 2026-08-08: resume_offset stayed at 28700161 (the hiberfile) while
# only /swap/swapfile (28599552) was active.
ExecStart=-/usr/bin/sh -c 'echo 0:0 > /sys/power/resume; echo 0 > /sys/power/resume_offset'

[Install]
WantedBy=hibernate.target
EOF

# Without this, a failure to activate the reserved file would let hibernation
# proceed against the 24G everyday file and quietly lose the guarantee. Requires
# turns that into a refusal to hibernate, which is visible.
install -d -o root -g root -m 0755 /etc/systemd/system/systemd-hibernate.service.d
install -o root -g root -m 0644 /dev/stdin \
    /etc/systemd/system/systemd-hibernate.service.d/50-require-hiberfile.conf <<'EOF'
# Abort hibernation rather than silently falling back to the everyday swapfile
# if the reserved file could not be activated.
[Unit]
Requires=hibernate-preparation.service
After=hibernate-preparation.service
EOF

systemctl daemon-reload
systemctl enable hibernate-preparation.service hibernate-resume.service

say "dracut resume module"
install -o root -g root -m 0644 /dev/stdin /etc/dracut.conf.d/resume.conf <<'EOF'
# Required for hibernation: puts the resume machinery into the initramfs.
add_dracutmodules+=" resume "
EOF
dracut -f --regenerate-all

say "verify"
printf 'sleep states       %s\n' "$(cat /sys/power/state)"
printf 'disk modes         %s\n' "$(cat /sys/power/disk)"
printf 'image_size         %s\n' "$(cat /sys/power/image_size)"
printf 'hiberfile present  %s (%s)\n' "$([[ -f $HIBERFILE ]] && echo yes || echo NO)" \
    "$(du -h --apparent-size "$HIBERFILE" 2>/dev/null | cut -f1)"
printf 'hiberfile active   %s (should be no -- it activates only at hibernate)\n' \
    "$(swapon --show=NAME --noheadings | grep -qF "$HIBERFILE" && echo YES || echo no)"
printf 'units enabled      %s %s\n' \
    "$(systemctl is-enabled hibernate-preparation.service)" \
    "$(systemctl is-enabled hibernate-resume.service)"

say "dry run of the preparation unit"
# Proves the reservation works before trusting it during an actual hibernate.
systemctl start hibernate-preparation.service
swapon --show
echo
echo "The line above must show $HIBERFILE at PRIO $HIBERPRIO with USED 0B."
swapoff "$HIBERFILE"
echo "deactivated again."

say "done"
cat <<'EOF'
Now TEST IT -- TWICE IN A ROW. A broken resume looks exactly like a normal boot,
and a stale resume pointer only shows up on the SECOND hibernate of a boot, so
a single cycle proves nothing about the second.

  1. Open something identifiable (a file in nvim, a few terminal tabs).
  2. sudo systemctl hibernate      -> power on -> session should return
  3. sudo systemctl hibernate      -> power on -> session should return AGAIN

Worked = your session comes back both times.
Failed = fresh login with nothing open, or the second call refuses with
         "Specified resume device is missing or is not an active swap device"

If it fails, in this order:

  journalctl -b -1 -u systemd-hibernate.service
  journalctl -b -1 -u hibernate-preparation.service   # did the reserve activate
  bootctl status | grep -i hibernate                  # was HibernateLocation set
  cat /sys/power/resume                               # 0:0 means nothing selected

Check the reservation is still intact at any time:

  swapon --show      # hiberfile should be ABSENT while you are working
EOF
