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
ROCKNIX patch rev are a matched pair: ROCKNIX's
`projects/ROCKNIX/packages/linux/package.mk` H700 case dictates the kernel
version the patches target. Confirmed at the current pinned rev:

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

The single inventory lives in a new `docs/version-pins.md`.

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

`nix-update --flake --commit <attr>` with default `--version=stable` fits
stable-tag packages. Most pins here are unstable-branch (`0-unstable-DATE`) or
constrained-tag, each needing a different non-default flag. Encoding the flag in
each package's `passthru.updateScript` keeps the CI runner uniform
(`--use-update-script` for everything) and puts the update logic next to the
package. `nix-update` runs `passthru.updateScript`, exporting
`UPDATE_NIX_ATTR_PATH` / `UPDATE_NIX_OLD_VERSION` to the script.

## Pin inventory and tiers

The bumpable packages live in `legacyPackages.aarch64-linux.*` (the overlay);
`flake.nix` only exposes `r36h-image` / `rg28xx-image` under `packages.*`. The
allowlist therefore targets `legacyPackages` attrs explicitly.

| Package | Fetch | Current pin | Tier | Update mechanism |
|---|---|---|---|---|
| `flycast2021` (main src) | fetchFromGitHub (branch) | `0-unstable-2025-01-16` | scripted | `nix-update --version=branch` |
| `emulationstation-fcamod` | fetchFromGitHub (351v) | `0-unstable-2026-04-07` | scripted | `nix-update --version=branch=351v` |
| `gptokeyb2` | fetchFromGitHub (branch) | `0.2.0-unstable-2025-09-22` | scripted | `nix-update --version=branch` |
| `mali-kbase` | fetchFromGitHub (branch) | `0-unstable-2026-04-06` | scripted | `nix-update --version=branch` |
| `es-theme-gbz35-mod` | fetchFromGitHub (rev, no `version`) | `4605d68` | scripted | add `version` attr; `--version=branch` |
| `libmali` | fetchFromGitHub (tag) | `g13p0` | scripted | `nix-update --version-regex 'g([0-9]+p[0-9]+)'` |
| `SDL2_classic` | fetchFromGitHub (tag) | `release-2.32.6` | scripted | `nix-update --version-regex 'release-2\.(.*)'` (stays on 2.x; never SDL3) |
| `linux-h700` | fetchurl kernel + fetchFromGitHub sparseCheckout | `7.0.11` + rev `2b61fed` | custom | `pkgs/linux-h700/update.sh` (parses `package.mk`) |
| `drastic` | fetchurl raw URL w/ embedded commit | `2.5.0.4` | manual | inventory note (no version source) |
| `freeimage` | fetchsvn | rev `1911` | manual | inventory note (nix-update has no SVN) |
| `u-boot-rg28xx-rocknix` | local blob | ROCKNIX image extract | manual | inventory note |
| `rg28xx-panel-firmware` | local blob | ROCKNIX image extract | manual | inventory note |
| `linux-rk3326` | `linuxPackages_latest` | tracks nixpkgs | out of scope | covered by `update-flake-lock` |

The `flycast2021` ROCKNIX `fetchpatch` URLs are pinned to a separate ROCKNIX
commit; they are left as-is by `nix-update` (it only touches the package `src`)
and do not need to move with the main source.

## How `linux-h700/update.sh` works

Referenced as `passthru.updateScript` on `linux-h700`. Steps:

1. Resolve the new ROCKNIX `distribution` rev (latest commit on the configured
   branch).
2. Fetch `projects/ROCKNIX/packages/linux/package.mk` at that rev and parse the
   `H700|…)` case → `PKG_VERSION`.
3. Recompute hashes: ROCKNIX sparseCheckout (`nurl`/`nix-prefetch`) and the
   kernel tarball from kernel.org.
4. Rewrite in `default.nix`: `rev`, both hashes, `version`, `modDirVersion`.
5. **Patch-list drift check**: diff the filenames present in
   `…/H700/patches/linux/` at the new rev against the hand-maintained
   `patches = [ … ]` array. If upstream added or removed patches, fail loudly —
   reconciling the list is a human decision, not an auto-apply.

A `--dry-run` mode prints the parsed version and the would-be diff without
writing, so the script is testable locally.

## CI wiring

New `.github/workflows/update-packages.yml`, scheduled (offset from the 2am
`update-flake-lock` job), reusing the `GH_TOKEN_FOR_UPDATES` secret. A single
job that, for each allowlisted attr, runs
`nix-update --flake --use-update-script --commit legacyPackages.aarch64-linux.<attr>`,
then opens one combined PR via `peter-evans/create-pull-request` (labels:
`dependencies`, `automated`). `nix-update`'s `--use-update-script` resolves the
script via `<nixpkgs>`, so the job sets `inputs-from: nixpkgs` (as the
`nix-packages` action already does).

The PR is built by `buildbot-nix` over webhook (real aarch64): it builds the
flake `checks.{nixos-r36h,nixos-rg28xx}` toplevels and the images. A bump that
breaks (e.g. patch application after a ROCKNIX rev move) shows as a red PR rather
than a broken `main`. The h700 patch-drift check is a cheap early signal in the
update job before the PR is even opened.

## Trade-offs

**Wins:**
- Single inventory of every pin and how it bumps.
- No pin floats silently — `linux-rk3326` aside, every pin is fixed and bumped
  deliberately.
- The coupling that caused #47 is handled in one script with a drift guard.
- Reuses tooling already trusted in `nix-packages`; minimal new config.

**Costs:**
- One `passthru.updateScript` per scripted package (one line each) plus the
  `linux-h700` script.
- The combined PR reds entirely if any single pin's bump breaks the build; the
  bad pin must be split out by hand to merge the rest. Accepted for simplicity.
- Manual tier (drastic, freeimage, blobs) still bumps by hand — documented, not
  automated.

## Implementation plan (high level)

1. Write `docs/version-pins.md` (the inventory); refresh the stale
   `pkgs/kernel-rk3326` reference in `docs/external-dependencies.md`.
2. Add `passthru.updateScript` to the seven scripted packages; add a `version`
   attr to `es-theme-gbz35-mod`.
3. Write `pkgs/linux-h700/update.sh` with the `package.mk` parse + patch-drift
   check + `--dry-run`; wire as `linux-h700`'s `passthru.updateScript`.
4. Add `.github/workflows/update-packages.yml`.
5. Validate each `updateScript` locally
   (`nix-update --flake --use-update-script <attr> --version=skip` for hashes;
   `update.sh --dry-run` for h700).

## Open questions

- **CI shape**: inline workflow in this repo (self-contained) vs extending
  `devusb/nix-update-action` to pass `--use-update-script` and accept a
  `legacyPackages` allowlist. Inline is recommended unless we want to upstream
  the change into the shared action.
- **`--use-update-script` + `--flake` + `<nixpkgs>`**: confirm at implementation
  that the script resolution finds nixpkgs in the Action environment.
- **`es-theme-gbz35-mod` version attr**: confirm `nix-update` writes the new
  `0-unstable-DATE` correctly once a `version` attribute exists.
- **`libmali` / `mali-kbase`**: these track ROCKNIX repos; confirm the
  branch/regex choice matches how upstream tags/branches them before enabling
  auto-bump.
