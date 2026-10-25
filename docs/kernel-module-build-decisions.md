# Kernel module build decisions

Choices made while updating the out-of-tree module packages and libmali for nixpkgs `02c087f`.

## Module install

`panel-generic-dsi`, `rocknix-joypad` and `mali-kbase` build with `kernel.commonMakeFlags` and install with the kernel's `modules_install` target, using `INSTALL_MOD_PATH=$out` and `INSTALL_MOD_DIR=extra`. `commonMakeFlags` overrides the kernel's `cmd_sign` with `kmodigest`, which writes a `<module>.ko.cer` next to each installed module. The nixpkgs module aggregator concatenates these into `modules.cer` and fails when one is missing.

`kernel.commonMakeFlags` is used instead of `kernelModuleMakeFlags` because the packages are called from `overlay.nix` with an explicit `kernel`, outside a `linuxPackagesFor` scope. `-C` and `M=` are passed directly, so the `KBUILD_OUTPUT` entry that `kernelModuleMakeFlags` adds is not needed.

`mali_kbase.ko` installs to `extra/mali_kbase.ko`. It is loaded by name through `boot.kernelModules`.

## Kernel API

The R36H kernel follows `linuxPackages_latest`, which is 7.3 at this nixpkgs rev.

- `panel-generic-dsi` calls `drm_of_get_panel_orientation` from `<drm/drm_of.h>`, the 7.3 name of `of_drm_get_panel_orientation`.
- `rocknix-singleadc-joypad` declares `MODULE_IMPORT_NS("IIO_CONSUMER")`. It also builds against the RG28XX 7.2 kernel with this line.

## libmali patchelf

libmali builds with `patchelfUnstable` (0.18.0) on its `PATH`. patchelf 0.19 rejects the prebuilt blob because `.dynsym` and `.hash` are not at naturally aligned file offsets. 0.18.0 completes both the `--set-rpath` in `postInstall` and the fixup phase's `--shrink-rpath` on the same file.
