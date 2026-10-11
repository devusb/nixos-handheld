# Version Pins

Every external source pinned by rev/version/hash, where it lives, and how it
bumps. Bumps run via `.github/workflows/update-packages.yml` (scripted tier) or
by hand (manual tier). See `docs/external-dependencies.md` for the provenance of
imported blobs/patches.

## Scripted tier — auto-bumped via nix-update

Each fetch-based package has a `passthru.updateScript`. The scheduled workflow
uses `gepbird/nix-update-action`, which runs
`nix-update --flake --use-update-script --commit legacyPackages.aarch64-linux.<attr>`
for each package on an aarch64 runner, substituting from the attic cache
buildbot fills, and opens one combined PR; buildbot-nix builds it on aarch64.

| Package | File | Upstream | Tracks | updateScript flags |
|---|---|---|---|---|
| `emulationstation-fcamod` | `pkgs/emulationstation-fcamod/default.nix` | christianhaitian/EmulationStation-fcamod | `351v` branch HEAD | `--version=branch=351v` |
| `gptokeyb2` | `pkgs/gptokeyb2/default.nix` | PortsMaster/gptokeyb2 | latest release tag | nix-update default |
| `es-theme-gbz35-mod` | `pkgs/es-theme-gbz35-mod/default.nix` | Jetup13/es-theme-gbz35_mod | branch HEAD | `--version=branch` |
| `SDL2_classic` | `pkgs/SDL2_classic/default.nix` | libsdl-org/SDL | 2.x release tags | `update.sh` (lists `release-2.*` tags) |
| `linux-h700` | `pkgs/linux-h700/default.nix` | ROCKNIX/distribution | `next` branch HEAD | `update.sh` (see below) |

### linux-h700 — kernel version and ROCKNIX rev move together

The kernel is built wholesale from one ROCKNIX rev (patches, device trees and
kernel config), and ROCKNIX's `projects/ROCKNIX/packages/linux/package.mk`
H700 case dictates the kernel version and its version-specific patch
directories. `update.sh` resolves the latest ROCKNIX `next` rev, parses the H700
case for `PKG_VERSION` and `PKG_PATCH_DIRS+=` entries, recomputes the
sparseCheckout hash (and the kernel tarball hash when the version changes), and
rewrites `rev`, `version`, `modDirVersion`, `versionPatchDirs` and the hashes.
It prints the patches added and removed between the two revs, and fails when
`package.mk` changes its patch-directory structure in a way it does not mirror.
Run `pkgs/linux-h700/update.sh --dry-run` to see a bump without writing it.

## Manual tier — bump by hand

| Package | File | Upstream | Why manual | How to bump |
|---|---|---|---|---|
| `libmali` | `pkgs/libmali/default.nix` | ROCKNIX/libmali | ROCKNIX-tracked; kept manual for now | edit `rev`+`hash`; `nurl https://github.com/ROCKNIX/libmali <rev>` |
| `mali-kbase` | `pkgs/mali-kbase/default.nix` | ROCKNIX/mali_kbase | ROCKNIX-tracked; kept manual for now | edit `rev`+`hash`; `nurl https://github.com/ROCKNIX/mali_kbase <rev>` |
| `drastic` | `pkgs/drastic/default.nix` | ROCKNIX/packages raw tarball | version not tied to a tag/release nix-update can read | edit the commit in the `url` + `hash`; `nix-prefetch-url <url>` then `nix hash to-sri --type sha256 <hash>` |
| `libretro.flycast2021` | `pkgs/flycast2021/default.nix` | metallic77/flycast | the pinned commit is not on any upstream branch, so `--version=branch` would move it backwards | edit `rev`+`hash`+`version`; `nurl https://github.com/metallic77/flycast <rev>` |
| `freeimage` | `pkgs/freeimage/default.nix` | SourceForge SVN | nix-update has no SVN version source | edit `rev`+`hash` |
| `u-boot-rg28xx-rocknix` | `pkgs/u-boot-rg28xx-rocknix/default.nix` | extracted from ROCKNIX image | local blob, no fetcher | re-extract from a newer ROCKNIX image |
| `rg28xx-panel-firmware` | `pkgs/rg28xx-panel-firmware/default.nix` | extracted from ROCKNIX image | local blob, no fetcher | re-extract from a newer ROCKNIX image |

## Out of scope

- `linux-rk3326` — tracks `linuxPackages_latest`; moves with `flake.lock` via
  `.github/workflows/update-flake-lock.yml`.
- The `flycast2021` ROCKNIX `fetchpatch` URLs pin a separate ROCKNIX commit
  and need not move with the main src.
