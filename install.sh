#!/usr/bin/env bash
set -euo pipefail

PKG_NAME="alc298-galaxybook"
PKG_VERSION="1.0"
SRC_DIR="/usr/src/${PKG_NAME}-${PKG_VERSION}"
KVER="$(uname -r)"
KBUILD_DIR="/usr/src/kernels/${KVER}"
WORKDIR="$(mktemp -d)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEC_VENDOR_EXPECTED="0x10ec0298"
CODEC_SUBSYSTEM_EXPECTED="0x144dc14f"

cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

echo "==> Checking for ALC298 codec with Samsung subsystem ${CODEC_SUBSYSTEM_EXPECTED}..."
codec_found=false
for node in /sys/class/sound/hwC*D*; do
    [ -r "$node/vendor_id" ] || continue
    if [ "$(cat "$node/vendor_id")" = "$CODEC_VENDOR_EXPECTED" ] && \
       [ "$(cat "$node/subsystem_id" 2>/dev/null)" = "$CODEC_SUBSYSTEM_EXPECTED" ]; then
        codec_found=true
        break
    fi
done
if ! $codec_found; then
    echo "ERROR: ALC298 with subsystem ${CODEC_SUBSYSTEM_EXPECTED} was not found on this system." >&2
    exit 1
fi
echo "    Found."

echo "==> Checking for conflicting model= overrides in /etc/modprobe.d..."
if grep -rn "model=" /etc/modprobe.d/ 2>/dev/null | grep -qi "snd-hda-intel\|snd_hda_intel"; then
    echo "WARNING: found an explicit 'model=' override for snd-hda-intel in /etc/modprobe.d/."
    echo "This takes priority over the PCI-subsystem-ID quirk this patch relies on and will"
    echo "silently prevent it from ever being selected. Likely left over from an older"
    echo "userspace audio workaround. Find and remove/comment it out before continuing:"
    grep -rn "model=" /etc/modprobe.d/ 2>/dev/null | grep -i "snd-hda-intel\|snd_hda_intel"
    exit 1
fi

echo "==> Installing build dependencies..."
sudo dnf install -y dkms patch gcc make "kernel-devel-${KVER}" curl tar xz

if [ ! -d "$KBUILD_DIR" ]; then
    echo "ERROR: ${KBUILD_DIR} not found even after installing kernel-devel-${KVER}." >&2
    echo "Your running kernel and installed kernel-devel may be out of sync (common right" >&2
    echo "after a kernel update, before reboot). Reboot and retry." >&2
    exit 1
fi

KVER_BASE="$(echo "$KVER" | sed -E 's/-.*//')"
KMAJOR="$(echo "$KVER_BASE" | cut -d. -f1)"
TARBALL="linux-${KVER_BASE}.tar.xz"
URL="https://cdn.kernel.org/pub/linux/kernel/v${KMAJOR}.x/${TARBALL}"

echo "==> Fetching vanilla kernel source for ${KVER_BASE} (needed: sound/hda/codecs + sound/hda/common)..."
echo "    ${URL}"
curl -fL -o "${WORKDIR}/${TARBALL}" "$URL"
tar -xf "${WORKDIR}/${TARBALL}" -C "$WORKDIR" \
    "linux-${KVER_BASE}/sound/hda/codecs" \
    "linux-${KVER_BASE}/sound/hda/common"

echo "==> Applying ALC298 Galaxy Book 12/10.6 quirk patch..."
patch -p1 -d "${WORKDIR}/linux-${KVER_BASE}" < "${SCRIPT_DIR}/patches/0001-sound-hda-realtek-galaxy-book12.patch"

echo "==> Staging DKMS source tree at ${SRC_DIR}..."
sudo rm -rf "$SRC_DIR"
sudo mkdir -p "$SRC_DIR/sound/hda"
sudo cp -a "${WORKDIR}/linux-${KVER_BASE}/sound/hda/codecs" "$SRC_DIR/sound/hda/"
sudo cp -a "${WORKDIR}/linux-${KVER_BASE}/sound/hda/common" "$SRC_DIR/sound/hda/"

sudo tee "$SRC_DIR/dkms.conf" > /dev/null <<EOF
PACKAGE_NAME="${PKG_NAME}"
PACKAGE_VERSION="${PKG_VERSION}"
BUILT_MODULE_NAME[0]="snd-hda-codec-alc269"
BUILT_MODULE_LOCATION[0]="sound/hda/codecs/realtek"
DEST_MODULE_LOCATION[0]="/updates/sound/hda/codecs/realtek"
AUTOINSTALL="yes"
MAKE[0]="make -C \${kernel_source_dir} M=\${dkms_tree}/\${PACKAGE_NAME}/\${PACKAGE_VERSION}/build/sound/hda/codecs/realtek modules"
EOF

echo "==> Registering with DKMS..."
sudo dkms remove -m "$PKG_NAME" -v "$PKG_VERSION" --all 2>/dev/null || true
sudo dkms add -m "$PKG_NAME" -v "$PKG_VERSION"
sudo dkms build -m "$PKG_NAME" -v "$PKG_VERSION"
sudo dkms install -m "$PKG_NAME" -v "$PKG_VERSION"

echo "==> Removing any leftover static install from fxjosemi's install-native.sh, if present..."
sudo rm -f "/usr/lib/modules/${KVER}/updates/alc298-book12/snd-hda-codec-alc269.ko"
sudo rmdir "/usr/lib/modules/${KVER}/updates/alc298-book12" 2>/dev/null || true

echo "==> Loading module..."
sudo modprobe -r snd_hda_codec_alc269 2>/dev/null || true
sudo modprobe snd_hda_codec_alc269
sleep 1

echo "==> Verifying..."
CODEC_SUBSYSTEM_COLON="${CODEC_SUBSYSTEM_EXPECTED:2:4}:${CODEC_SUBSYSTEM_EXPECTED:6:4}"
if dmesg -T | grep -q "picked fixup.*for PCI SSID ${CODEC_SUBSYSTEM_COLON}"; then
    echo "    SUCCESS: fixup picked via PCI SSID match."
else
    echo "WARNING: could not confirm the fixup was picked via dmesg. Check manually:"
    echo "    dmesg -T | grep -iE 'alc298|picked fixup'"
fi

echo "==> Done. This module will now rebuild automatically on future kernel updates via DKMS."
