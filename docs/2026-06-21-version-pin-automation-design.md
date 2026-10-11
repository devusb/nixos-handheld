# Version Pin Enumeration & Automated Bumps Design

Addresses [#47](https://github.com/devusb/nixos-handheld/issues/47).

## Problem

Several `pkgs/` entries pin external sources by rev/version/hash that must be
kept in sync by hand. This is fragile, and it has already bitten us: `linux-h700`
floated its kernel via `linuxPackages_latest` while the ROCKNIX patch series is
rev-pinned, so a nixpkgs kernel bump broke patch application.

Two distinct needs:

1. **Enumeration** — there is no single place that lists every external pin,
   what it tracks, and how to bump it. `docs/external-dependencies.md` documents
   *provenance* of imported blobs/patches, not the rev/version/hash pins, and is
   partly stale (refers to `pkgs/kernel-rk3326`, now `linux-rk3326`).
2. **Automation** — bumps are manual. We want drift surfaced and bumps opened as
   PRs for review, not auto-merged.

### The coupling constraint

The `linux-h700` kernel pin is **not independent**. The kernel version and the
ROCKNIX rev are a matched pair: ROCKNIX's
`projects/ROCKNIX/packages/linux/package.mk` H700 case dictates the kernel
version the patches target, for example:

```make
H700|S922X|SM8250|SM8650|SM8750|SM8550|SM6115)
    PKG_VERSION="7.0.11"
    PKG_URL="https://www.kernel.org/pub/linux/kernel/v${PKG_VERSION/.*/}.x/${PKG_NAME}-${PKG_VERSION}.tar.xz"
```

A ROCKNIX rev bump must read the new `package.mk` H700 case and re-pin the kernel
version + hash to match. No off-the-shelf updater infers this coupling.

## Solution

Drive bumps with **`nix-update`** (already used and trusted in
`devusb/nix-packages`), giving each bumpable package a `passthru.updateScript`
that declares *how* it updates. A scheduled GitHub Action runs
`nix-update --flake --use-update-script` over an explicit allowlist, commits the
results, and opens **one combined PR** (mirroring the existing
`nix-packages` action and `update-flake-lock`). `buildbot-nix` builds the PR on
real aarch64 via webhook, providing the build gate; a human merges only when
green. Nothing auto-merges.

The single inventory lives in `docs/version-pins.md`.

### Why nix-update over Renovate

- nix-update's version sources are GitHub, GitLab, Gitea, Bitbucket, Sourcehut,
  crates.io, npm, PyPI, RubyGems, Savannah — covering all the github-hosted pins
  here. It recomputes SRI hashes itself.
- Renovate's built-in Nix support is flake.lock-only. The `pkgs/` rev+hash pairs
  would need custom regex managers + a datasource per pin + post-upgrade hooks
  that shell out to nix-update/nurl to recompute hashes (Renovate cannot compute
  SRI hashes). That is strictly more config and re-implements nix-update. The
  coupling still needs a custom hook either way.
- We already run `nix-update` in CI for `nix-packages`, so this is the minimal
  incremental path.

### Why per-package `passthru.updateScript`

Pins here differ in what they track (release tags, a branch HEAD, a
constrained tag series), each needing different nix-update flags or a small
custom script. Encoding that in each package's `passthru.updateScript` keeps
the CI runner uniform (`--use-update-script` for everything) and puts the
update logic next to the package.

## Pin inventory and tiers

The bumpable packages live in `legacyPackages.<system>.*` (the overlay), which
the flake exposes for every system so nix-update runs native tooling on the
x86_64 GitHub runner.

| Package | Tracks | Tier | Update mechanism |
|---|---|---|---|
| `emulationstation-fcamod` | `351v` branch HEAD | scripted | `nix-update --version=branch=351v` |
| `gptokeyb2` | release tags | scripted | `nix-update` default (latest release) |
| `es-theme-gbz35-mod` | branch HEAD | scripted | `nix-update --version=branch` |
| `SDL2_classic` | 2.x release tags | scripted | `update.sh` listing `release-2.*` tags (never SDL3) |
| `linux-h700` | ROCKNIX `next` | scripted | `pkgs/linux-h700/update.sh` |
| `libretro.flycast2021` | pinned commit | manual | the pin is not on any upstream branch |
| `libmali`, `mali-kbase` | ROCKNIX | manual | kept manual for now |
| `drastic` | raw URL with embedded commit | manual | no version source |
| `freeimage` | SVN rev | manual | nix-update has no SVN source |
| `u-boot-rg28xx-rocknix`, `rg28xx-panel-firmware` | local blobs | manual | re-extract from a ROCKNIX image |
| `linux-rk3326` | `linuxPackages_latest` | out of scope | covered by `update-flake-lock` |

## How `linux-h700/update.sh` works

The kernel is built wholesale from one ROCKNIX rev: the shared and H700 patch
directories, H700 device trees and kernel config. The script:

1. Resolves the latest commit on ROCKNIX `next`; exits if unchanged.
2. Fetches `projects/ROCKNIX/packages/linux/package.mk` at that rev and parses
   the H700 case for `PKG_VERSION` and `PKG_PATCH_DIRS+=` entries.
3. Builds `versionPatchDirs` from those entries plus the directory named
   exactly after the version, if present.
4. Recomputes the sparseCheckout hash, and the kernel tarball hash when the
   version changes.
5. Rewrites `rev`, `version`, `modDirVersion`, `versionPatchDirs` and the
   hashes in `default.nix`.
6. Prints the patches added and removed between the two revs, and fails when
   `package.mk` changes its patch-directory structure in a way the package
   does not mirror.

`--dry-run` prints the resolved values without writing.

## CI wiring

`.github/workflows/update-packages.yml` runs daily after `update-flake-lock`.
It installs Nix with `cachix/install-nix-action` and sets
`NIX_PATH=nixpkgs=flake:nixpkgs` and `GITHUB_TOKEN` for the update scripts.
`gepbird/nix-update-action` then runs
`nix-update --flake --use-update-script --commit legacyPackages.x86_64-linux.<attr>`
for each scripted attr and opens one combined PR with the
`GH_TOKEN_FOR_UPDATES` secret.

The PR is built by `buildbot-nix` over webhook (real aarch64): it builds the
flake `checks.{nixos-r36h,nixos-rg28xx}` toplevels and the images. A bump that
breaks shows as a red PR rather than a broken `main`.

The workflow runs locally with `act` from a plain clone (not a worktree)
using the non-root runner image:

```sh
act workflow_dispatch -W .github/workflows/update-packages.yml \
  -P ubuntu-latest=ghcr.io/catthehacker/ubuntu:runner-latest \
  -s GITHUB_TOKEN="$(gh auth token)"
```

Without `GH_TOKEN_FOR_UPDATES` the final PR step fails; every update step
before it runs normally.

## Trade-offs

**Wins:**
- Single inventory of every pin and how it bumps.
- No pin floats silently — `linux-rk3326` aside, every pin is fixed and bumped
  deliberately.
- The coupling that caused #47 is handled in one script with structure guards.
- Reuses tooling already trusted in `nix-packages`; minimal new config.

**Costs:**
- One `passthru.updateScript` per scripted package plus the `linux-h700`
  script.
- The combined PR reds entirely if any single pin's bump breaks the build; the
  bad pin must be split out by hand to merge the rest. Accepted for simplicity.
- `linux-h700` bumps whenever ROCKNIX `next` moves, even when no H700 paths
  changed. Accepted.
- Manual tier (flycast2021, drastic, freeimage, blobs) still bumps by hand —
  documented, not automated.

## Decisions

- **CI shape**: `gepbird/nix-update-action`, a maintained fork of
  `selfuryon/nix-update-action` that runs each package's `passthru.updateScript`,
  installed with `cachix/install-nix-action` (the action's package install step
  failed with the Determinate installer when tested).
- **`libmali` / `mali-kbase`**: kept in the manual tier for now; revisit
  auto-bumping these ROCKNIX-tracked libs as a follow-up.
- **Tags vs. branches**: track release tags where upstream publishes them,
  branch HEAD otherwise.
