# Version Pins

Every external source pinned by rev/version/hash, where it lives, and how it
bumps. Bumps run via `.github/workflows/update-packages.yml` (scripted tier) or
by hand (manual tier). See `docs/external-dependencies.md` for the provenance of
imported blobs/patches.

## Scripted tier — auto-bumped via nix-update

Each fetch-based package has a `passthru.updateScript`. The scheduled workflow
runs `nix-update --flake --use-update-script --commit legacyPackages.x86_64-linux.<attr>`
(x86_64 so the tooling runs natively on the GitHub runner; the flake exposes
both aarch64 and x86_64 `legacyPackages`) and opens one combined PR; buildbot-nix
builds it on aarch64.

| Package | File | Upstream | Tracks | updateScript flags |
|---|---|---|---|---|
| `libretro.flycast2021` | `pkgs/flycast2021/default.nix` | metallic77/flycast | branch HEAD (`0-unstable-DATE`) | `--version=branch` |
| `emulationstation-fcamod` | `pkgs/emulationstation-fcamod/default.nix` | christianhaitian/EmulationStation-fcamod | `351v` branch HEAD | `--version=branch=351v` |
| `gptokeyb2` | `pkgs/gptokeyb2/default.nix` | PortsMaster/gptokeyb2 | branch HEAD | `--version=branch` |
| `es-theme-gbz35-mod` | `pkgs/es-theme-gbz35-mod/default.nix` | Jetup13/es-theme-gbz35_mod | branch HEAD | custom script (bare fetch, no `src` for nix-update) |
| `SDL2_classic` | `pkgs/SDL2_classic/default.nix` | libsdl-org/SDL | 2.x release tags | `--version-regex 'release-2\.(.*)'` |

### linux-h700 — coupled, updated by its own script

`linux-h700` is an aarch64-only kernel; its real sources (the kernel tarball via
`fetchurl` and the ROCKNIX rev via `fetchFromGitHub`) are nested fetchers, not
the package `src`, so nix-update can't drive it. The workflow runs
`pkgs/linux-h700/update.sh` directly instead.

The kernel version and the ROCKNIX patch rev are a matched pair: ROCKNIX's
`projects/ROCKNIX/packages/linux/package.mk` H700 case dictates the kernel
version. `update.sh` resolves the latest ROCKNIX `next` rev, parses `package.mk`
for the H700 `PKG_VERSION`, recomputes the kernel tarball hash and the
sparseCheckout hash, rewrites all four values, and hard-fails if a patch the
build applies has disappeared upstream (a curated subset of the upstream patch
dir is applied; upstream additions are reported, not fatal).

## Manual tier — bump by hand

| Package | File | Upstream | Why manual | How to bump |
|---|---|---|---|---|
| `libmali` | `pkgs/libmali/default.nix` | ROCKNIX/libmali | ROCKNIX-tracked; kept manual for now | edit `rev`+`hash`; `nurl https://github.com/ROCKNIX/libmali <rev>` |
| `mali-kbase` | `pkgs/mali-kbase/default.nix` | ROCKNIX/mali_kbase | ROCKNIX-tracked; kept manual for now | edit `rev`+`hash`; `nurl https://github.com/ROCKNIX/mali_kbase <rev>` |
| `drastic` | `pkgs/drastic/default.nix` | ROCKNIX/packages raw tarball | version not tied to a tag/release nix-update can read | edit the commit in the `url` + `hash`; `nix-prefetch-url <url>` then `nix hash to-sri --type sha256 <hash>` |
| `freeimage` | `pkgs/freeimage/default.nix` | SourceForge SVN | nix-update has no SVN version source | edit `rev`+`hash` |
| `u-boot-rg28xx-rocknix` | `pkgs/u-boot-rg28xx-rocknix/default.nix` | extracted from ROCKNIX image | local blob, no fetcher | re-extract from a newer ROCKNIX image |
| `rg28xx-panel-firmware` | `pkgs/rg28xx-panel-firmware/default.nix` | extracted from ROCKNIX image | local blob, no fetcher | re-extract from a newer ROCKNIX image |

## Out of scope

- `linux-rk3326` — tracks `linuxPackages_latest`; moves with `flake.lock` via
  `.github/workflows/update-flake-lock.yml`.
- The `flycast2021` ROCKNIX `fetchpatch` URLs pin a separate ROCKNIX commit;
  `nix-update` leaves them untouched and they need not move with the main src.
