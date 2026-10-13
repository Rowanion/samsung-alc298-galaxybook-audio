#!/usr/bin/env bash
set -euo pipefail
PKG_NAME="alc298-galaxybook"
PKG_VERSION="1.0"

sudo modprobe -r snd_hda_codec_alc269 2>/dev/null || true
sudo dkms remove -m "$PKG_NAME" -v "$PKG_VERSION" --all
sudo rm -rf "/usr/src/${PKG_NAME}-${PKG_VERSION}"
echo "Removed. The distribution's stock snd_hda_codec_alc269 will be used (without the"
echo "Galaxy Book quirk) on next load."
