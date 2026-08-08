#!/usr/bin/env bash
# Step 1 of the hibernation rebuild: real swap on disk, zram out of the way,
# zswap in front of it.
#
# zswap is a compressed cache that sits IN FRONT of a swap device -- it is
# pointless without one, and pairing it with zram causes LRU inversion (pages
# get compressed into zram, then zswap compresses them again on the way out and
# the eviction order stops meaning anything). So all three changes belong in one
# reboot: create the swapfile, drop zram, turn zswap on.
#
# This creates ONLY the always-on 24G swapfile for everyday paging. The
# reserved 20G hibernation file is a separate concern -- see 03-hibernate.sh.
# The size here has nothing to do with whether hibernation works; that is
# guaranteed by the reserved file, not this one.
#
# Run with sudo. Safe to re-run: every step checks before acting, and a size
# change is applied by recreating the file (refused if pages are parked in it).

set -euo pipefail

SWAPDIR=/swap
SWAPFILE=$SWAPDIR/swapfile
SWAPSIZE=24G
PRIORITY=10

(( EUID == 0 )) || { echo "run with sudo" >&2; exit 1; }

say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

say "btrfs subvolume for swap"
# Its own subvolume so snapper never snapshots it -- a snapshotted swapfile
# breaks NOCOW and corrupts.
if btrfs subvolume show "$SWAPDIR" &>/dev/null; then
    echo "$SWAPDIR already a subvolume, leaving it"
else
    btrfs subvolume create "$SWAPDIR"
fi

# NOCOW must be set on the directory BEFORE any file inside it has data --
# chattr +C on a file that already has extents does nothing.
chattr +C "$SWAPDIR" 2>/dev/null || true
lsattr -d "$SWAPDIR"

# SELinux is Enforcing here. Without swapfile_t the kernel refuses the swapon
# with a permission error that does not mention SELinux at all.
#
# The fcontext rule must exist BEFORE any restorecon. /swap is not a path the
# shipped policy knows, so a bare restorecon relabels swapfile_t -> default_t,
# which is the opposite of what is wanted -- mkswap gets the label right and
# restorecon then undoes it.
if command -v semanage >/dev/null; then
    semanage fcontext -a -t swapfile_t "${SWAPDIR}(/.*)?" 2>/dev/null \
        || semanage fcontext -m -t swapfile_t "${SWAPDIR}(/.*)?" 2>/dev/null \
        || true
else
    echo "WARN: semanage missing (dnf install policycoreutils-python-utils)." >&2
    echo "      Skipping relabel rather than mislabelling to default_t." >&2
fi
command -v semanage >/dev/null && restorecon -Rv "$SWAPDIR" || true

say "swapfile ($SWAPSIZE)"
want_bytes=$(numfmt --from=iec "$SWAPSIZE")
have_bytes=$(stat -c%s "$SWAPFILE" 2>/dev/null || echo 0)

if [[ -f $SWAPFILE ]] && (( have_bytes == want_bytes )); then
    echo "$SWAPFILE already $SWAPSIZE, leaving it"
else
    if [[ -f $SWAPFILE ]]; then
        echo "resizing $SWAPFILE: $(numfmt --to=iec "$have_bytes") -> $SWAPSIZE"
        # Refuse if pages are actually parked in it. Swapping off would page
        # them back into RAM, and recreating the file while a hibernation image
        # references it would corrupt an unresumed session.
        used=$(awk -v f="$SWAPFILE" '$1==f {print $4}' /proc/swaps 2>/dev/null || echo 0)
        if [[ -n ${used:-} ]] && (( used > 0 )); then
            echo "ERROR: ${used}K in use. Reboot first, then re-run." >&2
            exit 1
        fi
        swapoff "$SWAPFILE" 2>/dev/null || true
        rm -f "$SWAPFILE"
    fi
    # mkswap --file creates, sizes and formats in one step. The old
    # truncate/chattr/fallocate/chmod/mkswap chain is no longer needed.
    mkswap --file --size "$SWAPSIZE" -L SWAPFILE "$SWAPFILE"
    chmod 600 "$SWAPFILE"
fi
# Only relabel once the fcontext rule above exists; otherwise this sets
# default_t and breaks the very thing it is meant to fix.
command -v semanage >/dev/null && restorecon -v "$SWAPFILE" || true

say "fstab"
if grep -qF "$SWAPFILE" /etc/fstab; then
    echo "already in fstab:"; grep -F "$SWAPFILE" /etc/fstab
else
    cp -a /etc/fstab "/etc/fstab.bak-$(date +%Y%m%d-%H%M%S)"
    printf '%s none swap defaults,pri=%s 0 0\n' "$SWAPFILE" "$PRIORITY" >> /etc/fstab
    echo "appended"
fi
systemctl daemon-reload

say "activate swapfile, then drop zram"
swapon --show
swapon "$SWAPFILE" 2>/dev/null || echo "(already on)"
# Order matters: the new file must be active before zram goes, or anything
# currently paged into zram has nowhere to land.
if swapon --show=NAME --noheadings | grep -q zram0; then
    swapoff /dev/zram0 && echo "zram0 off"
fi
systemctl mask systemd-zram-setup@zram0.service 2>&1 | tail -1
swapon --show

say "zswap on the kernel command line"
# This install is BLS, so two places need to agree: the existing boot entries
# (grubby) and the template future kernels are built from (/etc/kernel/cmdline).
# Updating only one leaves the setting working now and vanishing at the next
# kernel update, or vice versa.
ZSWAP_ARGS="zswap.enabled=1 zswap.compressor=zstd zswap.zpool=zsmalloc zswap.max_pool_percent=25"

grubby --update-kernel=ALL --args="$ZSWAP_ARGS"

cp -a /etc/kernel/cmdline "/etc/kernel/cmdline.bak-$(date +%Y%m%d-%H%M%S)"
current=$(cat /etc/kernel/cmdline)
for arg in $ZSWAP_ARGS; do
    key=${arg%%=*}
    # drop any existing value for this key, then append the new one
    current=$(printf '%s' "$current" | sed -E "s/(^| )${key}=[^ ]*//g")
    current="$current $arg"
done
printf '%s\n' "$(printf '%s' "$current" | tr -s ' ' | sed 's/^ //;s/ $//')" > /etc/kernel/cmdline

echo; echo "/etc/kernel/cmdline is now:"; cat /etc/kernel/cmdline
echo; echo "boot entry args:"; grubby --info=ALL | grep '^args=' | head -3

say "done -- nothing above takes effect for zswap until reboot"
cat <<'EOF'
After rebooting, confirm all four:

  swapon --show                                   # /swap/swapfile, prio 10, no zram0
  cat /sys/module/zswap/parameters/enabled        # Y
  cat /sys/module/zswap/parameters/compressor     # zstd
  systemctl is-enabled systemd-zram-setup@zram0.service   # masked

If zswap reads N after reboot, the argument reached the entry but the kernel
rejected it -- check `dmesg | grep -i zswap` for the reason before re-running.
EOF
