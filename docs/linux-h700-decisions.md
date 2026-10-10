# linux-h700 decisions

Choices made while switching `pkgs/linux-h700` to build the ROCKNIX H700 kernel wholesale.

## Patch directories and order

ROCKNIX's `scripts/unpack` builds its patch list from `PKG_PATCH_DIRS="${LINUX} mainline ${DEVICE} default"` plus `rocknix-joypad` for H700, then the directory matching the kernel version, then the device directory. `${LINUX}` is unset for the ROCKNIX project, and only `mainline` and `7.2` exist under `projects/ROCKNIX/packages/linux/patches`. The effective order for H700 is:

1. `projects/ROCKNIX/packages/linux/patches/mainline/*.patch`
2. `projects/ROCKNIX/packages/linux/patches/<major.minor>/*.patch`
3. `projects/ROCKNIX/devices/H700/patches/linux/*.patch`

The version directory is derived from `version` with `lib.versions.majorMinor`. Files ending in `.disabled` are skipped because they do not match `*.patch`.

## Kernel config

Their `devices/H700/linux/linux.aarch64.conf` is used as the base config. The edits from their `pre_make_target` that apply to us are mirrored: `INITRAMFS_SOURCE` and `DEFAULT_HOSTNAME` are cleared, and `EXTRA_FIRMWARE` lists what is staged in `external-firmware/`. Their distro feature toggles (swap, NFS, CIFS, iSCSI, WireGuard) are not mirrored; the config's own values are kept.

`localConfig` holds options layered on top. It contains only `USB_ETH=m`, which their config disables and which `g_ether` needs for SSH over USB. The build fails if a `localConfig` value does not survive `make olddefconfig`.

## Embedded firmware

The rg28xx panel blob replaces their list of Realtek Wi-Fi/Bluetooth and other-panel blobs. `regulatory.db` and its signature from `wireless-regdb` are embedded, as ROCKNIX does, because their config builds `CFG80211` in with `CFG80211_REQUIRE_SIGNED_REGDB`.

## Device tree

`pkgs/h700-dtb` compiles `rg28xx-nixos.dts`, which includes ROCKNIX's `sun50i-h700-anbernic-rg28xx.dts` and adds the CPU thermal cooling maps. The include resolves through the kernel source, where `linux-h700` copies `devices/H700/linux/dts`, matching their `post_patch`.

## Unchanged for now

The s2idle mmc rebind, the mmc1 runtime PM pin, `fbcon=rotate:3` and the kanshi transform stay in place. ROCKNIX's suspend series and rotation fix may make them unnecessary; each is to be removed separately after testing on the device.
