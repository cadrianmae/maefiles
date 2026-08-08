#!/usr/bin/env bash
# Step 2: proprietary NVIDIA driver on the hybrid Nitro AN517-51.
#
#   Intel UHD 630 (00:02.0)  primary
#   NVIDIA GTX 1650 Mobile (01:00.0)  render offload only
#
# Deliberately NOT done here, all per HARD-SETUPS.md:
#
#   * No NVreg_PreserveVideoMemoryAllocations / NVreg_TemporaryFilePath /
#     NVreg_UseKernelSuspendNotifiers. The 610.x driver sets sane values by
#     itself (PreserveVideoMemoryAllocations: 2, UseKernelSuspendNotifiers: 1)
#     and nvidia-hibernate.service has an ExecCondition that only takes the
#     legacy nvidia-sleep.sh path when the notifier flag is 0. Forcing the old
#     options back on selects the legacy path and can corrupt the framebuffer
#     on resume.
#   * No xorg.conf, no EnvyControl. Hybrid graphics runs via PRIME render
#     offload. This firmware lacks _PR3 so the dGPU cannot power off under
#     Linux at all -- that is a firmware limit, not something to fix here.
#
# Run with sudo. Do NOT reboot until the akmod has finished building.

set -euo pipefail

(( EUID == 0 )) || { echo "run with sudo" >&2; exit 1; }

say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

say "install"
# akmod, not kmod: akmods.service rebuilds the module on every kernel update.
# With kmod you get a black screen the first time the kernel moves ahead of it.
#
# -power is a SEPARATE package and is not pulled in by akmod-nvidia. It ships
# every suspend/hibernate unit plus systemd-hibernate.service.d/
# nvidia-suspend-nofreeze.conf -- without it hibernation resumes to a corrupted
# display. It is the whole reason NVIDIA comes before hibernation here.
#
# -cuda is the only package that ships nvidia-smi, which is how you check the
# dGPU at all. If you decide you do not want the CUDA libraries alongside it:
#   sudo dnf remove xorg-x11-drv-nvidia-cuda
dnf install -y akmod-nvidia xorg-x11-drv-nvidia \
               xorg-x11-drv-nvidia-power xorg-x11-drv-nvidia-cuda

say "wait for the module to build"
# This is the step people skip. RPM Fusion: "please remember to wait until the
# kmod has been built. This can take up to 5 minutes on some systems."
# Rebooting early boots to a black screen, because nouveau is blacklisted by
# then and nvidia does not exist yet.
wait_for_module() {
    for i in $(seq 1 "$1"); do
        modinfo nvidia &>/dev/null && return 0
        printf '\rwaiting for akmods... %ss ' "$((i * 5))"
        sleep 5
    done
    echo
    return 1
}

# The package install triggers the build itself, so wait for that first rather
# than starting a second one racing it.
if ! wait_for_module 36; then
    echo "no module after 3 minutes -- forcing a build"
    akmods --force 2>&1 | tail -20 || true
    wait_for_module 36 || true
fi

if ! modinfo nvidia &>/dev/null; then
    echo
    echo "ERROR: nvidia module still not built. DO NOT REBOOT." >&2
    echo "Check: journalctl -u akmods -b  and  ls /var/cache/akmods/nvidia/" >&2
    exit 1
fi
echo "nvidia module built: $(modinfo -F version nvidia)"
# Must resolve under the RUNNING kernel, not some older one left in /lib/modules.
modinfo -F filename nvidia

say "blacklist nouveau on the kernel command line"
# RPM Fusion's packaging blacklists nouveau by itself, so this is belt and
# braces for nouveau -- but NOT for nova_core, the Rust successor in recent
# kernels, which the packaging does not yet cover and which will bind the card
# instead. Set on the cmdline rather than in modprobe.d so it also applies
# inside the initramfs (rd.driver.blacklist).
#
# nvidia-drm.modeset=1 is already the RPM Fusion default and is deliberately
# NOT set here -- setting it by hand only matters if you want to disable it.
NVIDIA_ARGS="rd.driver.blacklist=nouveau,nova_core modprobe.blacklist=nouveau,nova_core"

grubby --update-kernel=ALL --args="$NVIDIA_ARGS"

# BLS again: grubby fixes the entries that exist, /etc/kernel/cmdline is the
# template the next kernel is built from. Both or neither.
cp -a /etc/kernel/cmdline "/etc/kernel/cmdline.bak-$(date +%Y%m%d-%H%M%S)"
current=$(cat /etc/kernel/cmdline)
for arg in $NVIDIA_ARGS; do
    key=${arg%%=*}
    current=$(printf '%s' "$current" | sed -E "s/(^| )${key}=[^ ]*//g")
    current="$current $arg"
done
printf '%s\n' "$(printf '%s' "$current" | tr -s ' ' | sed 's/^ //;s/ $//')" > /etc/kernel/cmdline
cat /etc/kernel/cmdline

say "power management units"
# These four handle VRAM save/restore across suspend and hibernate. All are
# needed; hibernation without them resumes to a corrupted display.
for u in nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service \
         nvidia-suspend-then-hibernate.service nvidia-powerd.service; do
    printf '%-34s ' "$u"
    if systemctl list-unit-files "$u" &>/dev/null && [[ -n $(systemctl list-unit-files "$u" --no-legend) ]]; then
        systemctl enable "$u" &>/dev/null && echo enabled
    else
        echo "not shipped by this driver build, skipping"
    fi
done

say "rebuild initramfs"
dracut -f --regenerate-all

say "done"
cat <<'EOF'
Reboot now. After it comes back, confirm:

  lsmod | grep -E '^(nvidia|nouveau)'      # nvidia present, nouveau ABSENT
  nvidia-smi                               # driver version, GPU listed
  glxinfo -B | grep -i 'device\|vendor'    # should still say Intel -- the dGPU
                                           # is offload-only, not the default
  __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia glxinfo -B \
                                           # this one should say NVIDIA

And the keyring fix from before the reboot:

  journalctl -b | grep gkr-pam             # "started properly and unlocked keyring"
  ps -eo pid,cmd | grep '[g]nome-keyring'  # --daemonize, NOT --foreground
EOF
