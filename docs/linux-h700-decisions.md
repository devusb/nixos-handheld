# linux-h700 decisions

Choices made while switching `pkgs/linux-h700` to build the ROCKNIX H700 kernel wholesale.

## Patch directories and order

ROCKNIX's `scripts/unpack` applies the directories named in `PKG_PATCH_DIRS` (`"${LINUX} mainline ${DEVICE} default"`, plus `rocknix-joypad` for H700 and any entries the H700 case of `package.mk` appends), then the directory named exactly after `PKG_VERSION`, then the device directory. `${LINUX}` is unset for the ROCKNIX project, and only the `mainline` and version directories exist under `projects/ROCKNIX/packages/linux/patches`. The effective order for H700 is:

1. `projects/ROCKNIX/packages/linux/patches/mainline/*.patch`
2. `projects/ROCKNIX/packages/linux/patches/<dir>/*.patch` for each entry of `versionPatchDirs`
3. `projects/ROCKNIX/devices/H700/patches/linux/*.patch`

`versionPatchDirs` lists the H700 case's `PKG_PATCH_DIRS+=` entries followed by the directory named after `PKG_VERSION` when it exists. For example, a `PKG_VERSION="7.2.9"` case with `PKG_PATCH_DIRS+=" 7.2.6"` applies `7.2.6` and no `7.2` directory. `update.sh` writes the list on each bump. Files ending in `.disabled` are skipped because they do not match `*.patch`.

## Kernel config

Their `devices/H700/linux/linux.aarch64.conf` is used as the base config. The edits from their `pre_make_target` that apply to us are mirrored: `INITRAMFS_SOURCE` and `DEFAULT_HOSTNAME` are cleared, and `EXTRA_FIRMWARE` lists what is staged in `external-firmware/`. Their distro feature toggles (swap, NFS, CIFS, iSCSI, WireGuard) are not mirrored; the config's own values are kept.

`localConfig` holds options layered on top. It contains only `USB_ETH=m`, which their config disables and which `g_ether` needs for SSH over USB. The build fails if a `localConfig` value does not survive `make olddefconfig`.

## Evaluation

`linuxManualConfig` is given `config = { CONFIG_MODULES = "y"; }` instead of parsing the generated config through import-from-derivation, so the package evaluates on any system without building anything. nixpkgs reads only `MODULES` and `RUST` from it. The NixOS `requiredKernelConfig` assertions are skipped because the kernel has `passthru.features`, and the firewall reverse-path check, the only other reader, is not enabled on the RG28XX.

The kernel `passthru` re-exports `version` and `src`, and the patched source carries the ROCKNIX rev as `passthru.rev`. nix-update finds the file to edit from where `version` and `src` are defined, and commits non-interactively only when `version` or `src.rev` changes.

## Embedded firmware

The rg28xx panel blob replaces their list of Realtek Wi-Fi/Bluetooth and other-panel blobs. `regulatory.db` and its signature from `wireless-regdb` are embedded, as ROCKNIX does, because their config builds `CFG80211` in with `CFG80211_REQUIRE_SIGNED_REGDB`.

## Device tree

`pkgs/h700-dtb` compiles `rg28xx-nixos.dts`, which includes ROCKNIX's `sun50i-h700-anbernic-rg28xx.dts` and adds the CPU thermal cooling maps. The include resolves through the kernel source, where `linux-h700` copies `devices/H700/linux/dts`, matching their `post_patch`.

## Unchanged for now

The s2idle mmc rebind, the mmc1 runtime PM pin, `fbcon=rotate:3` and the kanshi transform stay in place. ROCKNIX's suspend series and rotation fix may make them unnecessary; each is to be removed separately after testing on the device.

## Updater guards

`update.sh` mirrors only the parts of ROCKNIX's patch-directory logic that apply to H700 today. It fails instead of guessing when `package.mk` stops setting the expected global `PKG_PATCH_DIRS`, when the H700 case replaces `PKG_PATCH_DIRS` with `=`, or when top-level or `aarch64` patches appear under `projects/ROCKNIX/packages/linux/patches`. Each of these needs `patchDirs` in `default.nix` reviewed by hand.
