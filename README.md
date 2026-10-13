# samsung-alc298-galaxybook-audio

DKMS-packaged kernel patch that adds a proper Realtek HDA quirk for the ALC298
codec found in Samsung Galaxy Book devices (PCI subsystem ID `144d:c14f`).
Replaces the need for a userspace `hda-verb`-based amp-init hack (e.g. the
DarrenBenson speaker fix) with a native kernel driver: correct speaker/
headphone DAC routing, jack-based switching, and proper suspend/resume
handling.

Confirmed working on:

- Samsung Galaxy Book 10.6 (SM-W620) — left speaker, boot-time pop eliminated.
- Samsung Galaxy Book 12 (SM-W720/SM-W727) — original target, per
  [fxjosemi/Samsung-Galaxy-Book-12-Linux](https://github.com/fxjosemi/Samsung-Galaxy-Book-12-Linux).

The quirk matches purely on PCI subsystem ID (no DMI check at all), so it
applies correctly on any hardware reporting that exact codec/subsystem
combination.

## Known limitation (SM-W620 specific)

On at least one Samsung Galaxy Book 10.6 unit, the right speaker is
effectively non-functional (very faint/no output) under this driver. The
same right-channel issue was also present under the older DarrenBenson
userspace fix, so this is very likely a hardware/amp fault on the specific
unit rather than something this patch can fix. If your right speaker works
fine, this note doesn't apply to you — please report back either way.

Do not attempt to fix this by swapping the `0x31`/`0x34` amp-selector values
in the patch — this was tried and caused a channel-crossing regression without
restoring right-channel output. Revert via `git checkout` on the patch file if
you experiment with this.

## What it does

`install.sh`:

1. Checks that an ALC298 codec with subsystem ID `144d:c14f` is present.
2. Checks for a conflicting `model=` override in `/etc/modprobe.d/` (a common
   leftover from older userspace audio workarounds) — this silently overrides
   the PCI-subsystem-ID quirk table and must be removed first if present.
3. Installs build dependencies (`dkms`, `kernel-devel` matching your running
   kernel, etc.).
4. Downloads the matching vanilla kernel.org source for your exact kernel
   version, pulls `sound/hda/codecs/` and `sound/hda/common/` (the realtek
   codec needs helper files from sibling directories, not just itself).
5. Applies `patches/0001-sound-hda-realtek-galaxy-book12.patch`.
6. Registers `snd_hda_codec_alc269` as a DKMS module, so it rebuilds
   automatically on future kernel updates.
7. Removes any leftover static install from fxjosemi's own
   `install-native.sh` (different, non-DKMS install mechanism) if present.
8. Loads it and checks `dmesg` for confirmation the quirk was picked via PCI
   SSID match.

No kernel source is vendored in this repo — fetched fresh each run, so it
tracks whatever kernel you're actually running.

## Usage

```bash
git clone <this-repo>
cd samsung-alc298-galaxybook-audio
./install.sh
```

Before running this, disable any existing userspace audio fix (e.g.
DarrenBenson's) so it doesn't fight the native driver over the same amp
registers:

```bash
sudo systemctl disable --now galaxybook-audio.service
sudo systemctl disable --now galaxybook-jack-watch.service 2>/dev/null
sudo systemctl disable --now galaxybook-audio.sleep 2>/dev/null
```

To remove:

```bash
./uninstall.sh
```

## Credit

The patch (`patches/0001-sound-hda-realtek-galaxy-book12.patch`) is used
verbatim, unmodified, from
[fxjosemi/Samsung-Galaxy-Book-12-Linux](https://github.com/fxjosemi/Samsung-Galaxy-Book-12-Linux).
Their own installer (`kernel/install-native.sh`) does a static, non-DKMS
install relying on CachyOS-specific pacman hooks for rebuilding after kernel
updates; this repo instead wires the same patch into DKMS for
DKMS-supporting distros (Fedora included).

The underlying register-level amp research is originally from Aurélien Croc
(AP²C)'s Windows/QEMU trace work, per both this patch's upstream project and
the earlier DarrenBenson userspace fix — both trace back to the same source.

## License

GPL-2.0-only, matching the Linux kernel.
