# Version Pin Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enumerate every external version pin in one inventory and add `nix-update`-driven, PR-based automated bumps, with a custom updater for the coupled `linux-h700` kernel/ROCKNIX-rev pin.

**Architecture:** Each bumpable package carries a `passthru.updateScript` (via the `nix-update-script` helper) declaring its update flags. A scheduled GitHub Action runs `nix-update --flake --use-update-script --commit` over an explicit `legacyPackages.aarch64-linux.*` allowlist, commits each bump, and opens one combined PR. `buildbot-nix` builds the PR on real aarch64 as the gate; nothing auto-merges.

**Tech Stack:** Nix flakes, `nix-update` (1.15.x in nixpkgs-unstable), `nix-update-script` helper, GitHub Actions, `peter-evans/create-pull-request`, bash.

## Global Constraints

- Custom packages live in `legacyPackages.aarch64-linux.*` (the overlay); `flake.nix` exposes only `r36h-image`/`rg28xx-image` under `packages.*`. The allowlist targets `legacyPackages.aarch64-linux.<attr>` paths.
- Scripted tier (auto-bump): `flycast2021`, `emulationstation-fcamod`, `gptokeyb2`, `es-theme-gbz35-mod`, `SDL2_classic`, `linux-h700`.
- Manual tier (inventory only, no updateScript): `libmali`, `mali-kbase`, `drastic`, `freeimage`, `u-boot-rg28xx-rocknix`, `rg28xx-panel-firmware`. `linux-rk3326` is out of scope (covered by `update-flake-lock`).
- `nix-update-script` signature: `{ attrPath ? null, extraArgs ? [ ] }` → `[ nix-update ] ++ extraArgs ++ [attrPath?]`. It does NOT add `--flake`; put `--flake` in `extraArgs`.
- `SDL2_classic` must stay on the 2.x series — never SDL3. Its update is regex-constrained to `release-2.*`.
- Reuse the existing `GH_TOKEN_FOR_UPDATES` secret and labels `dependencies`, `automated` (as in `.github/workflows/update-flake-lock.yml`).
- Commit style: Conventional Commits, terse, imperative, no Claude co-author/footer.
- Commit structure: one foundational commit (docs + workflow), then one commit per package. No pin values change in this plan — these tasks add machinery only; actual bumps happen when the scheduled workflow runs.
- These tasks change only `passthru` (and one `version` attr); they do not alter build inputs, so they are safe to verify by flake eval. Functional kernel/image builds happen on the aarch64 remote builder / buildbot, not in these steps.

## File Structure

- Create: `docs/version-pins.md` — the single pin inventory (table + per-package bump notes).
- Modify: `docs/external-dependencies.md` — fix stale `pkgs/kernel-rk3326` → `pkgs/linux-rk3326` reference.
- Create: `.github/workflows/update-packages.yml` — scheduled bump workflow.
- Modify: `pkgs/flycast2021/default.nix` — add `nix-update-script` input + `passthru.updateScript`.
- Modify: `pkgs/emulationstation-fcamod/default.nix` — same, branch `351v`.
- Modify: `pkgs/gptokeyb2/default.nix` — same (uses `finalAttrs`).
- Modify: `pkgs/es-theme-gbz35-mod/default.nix` — add `nix-update-script` input, `passthru.version`, `passthru.updateScript`.
- Modify: `pkgs/SDL2_classic/default.nix` — same, regex-constrained (uses `finalAttrs`).
- Create: `pkgs/linux-h700/update.sh` — ROCKNIX-coupled updater.
- Modify: `pkgs/linux-h700/default.nix` — add inputs + `passthru.updateScript` wrapping `update.sh`.

---

### Task 1: Foundational — inventory doc, external-deps refresh, workflow

**Files:**
- Create: `docs/version-pins.md`
- Modify: `docs/external-dependencies.md` (line ~49)
- Create: `.github/workflows/update-packages.yml`

**Interfaces:**
- Produces: the `legacyPackages.aarch64-linux.<attr>` allowlist used by the workflow loop (`flycast2021 emulationstation-fcamod gptokeyb2 es-theme-gbz35-mod SDL2_classic linux-h700`). Later per-package tasks each add the `passthru.updateScript` the workflow invokes.

- [ ] **Step 1: Write the inventory doc**

Create `docs/version-pins.md`:

```markdown
# Version Pins

Every external source pinned by rev/version/hash, where it lives, and how it
bumps. Bumps run via `.github/workflows/update-packages.yml` (scripted tier) or
by hand (manual tier). See `docs/external-dependencies.md` for the provenance of
imported blobs/patches.

## Scripted tier — auto-bumped via nix-update

Each package has a `passthru.updateScript`. The scheduled workflow runs
`nix-update --flake --use-update-script --commit legacyPackages.aarch64-linux.<attr>`
and opens one combined PR; buildbot-nix builds it on aarch64.

| Package | File | Upstream | Tracks | updateScript flags |
|---|---|---|---|---|
| `flycast2021` | `pkgs/flycast2021/default.nix` | metallic77/flycast | branch HEAD (`0-unstable-DATE`) | `--version=branch` |
| `emulationstation-fcamod` | `pkgs/emulationstation-fcamod/default.nix` | christianhaitian/EmulationStation-fcamod | `351v` branch HEAD | `--version=branch=351v` |
| `gptokeyb2` | `pkgs/gptokeyb2/default.nix` | PortsMaster/gptokeyb2 | branch HEAD | `--version=branch` |
| `es-theme-gbz35-mod` | `pkgs/es-theme-gbz35-mod/default.nix` | Jetup13/es-theme-gbz35_mod | branch HEAD | `--version=branch` |
| `SDL2_classic` | `pkgs/SDL2_classic/default.nix` | libsdl-org/SDL | 2.x release tags | `--version-regex 'release-2\.(.*)'` |
| `linux-h700` | `pkgs/linux-h700/default.nix` | ROCKNIX/distribution + kernel.org | ROCKNIX rev; kernel version from `package.mk` | custom `update.sh` |

### linux-h700 coupling

The kernel version and the ROCKNIX patch rev are a matched pair: ROCKNIX's
`projects/ROCKNIX/packages/linux/package.mk` H700 case dictates the kernel
version. `pkgs/linux-h700/update.sh` bumps the ROCKNIX rev, parses `package.mk`
for the H700 `PKG_VERSION`, recomputes the kernel tarball hash and the
sparseCheckout hash, rewrites all four values, and fails loudly if upstream
added/removed patch files versus the hand-maintained `patches` array.

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
```

- [ ] **Step 2: Fix the stale reference in `docs/external-dependencies.md`**

The file refers to `pkgs/kernel-rk3326/patches/` (the kernel package is now `linux-rk3326`). Update the two `**Location:**` lines under "Kernel DTS Patch" and "Panel Driver" sections that say `pkgs/kernel-rk3326/...`.

Run to find them:

```bash
grep -n "kernel-rk3326" docs/external-dependencies.md
```

Replace each `pkgs/kernel-rk3326` with `pkgs/linux-rk3326` (the panel driver one is `pkgs/panel-generic-dsi/drivers/` already — only change actual `kernel-rk3326` occurrences). Use exact-string edits per match.

- [ ] **Step 3: Write the workflow**

Create `.github/workflows/update-packages.yml`:

```yaml
name: update-packages
on:
  workflow_dispatch:
  schedule:
    - cron: '0 3 * * *' # daily at 3am UTC, after update-flake-lock (2am)
jobs:
  packages:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      - name: Install Nix
        uses: DeterminateSystems/nix-installer-action@main
      - name: Run nix-update per package
        run: |
          set -uo pipefail
          attrs="flycast2021 emulationstation-fcamod gptokeyb2 es-theme-gbz35-mod SDL2_classic linux-h700"
          for a in $attrs; do
            echo "::group::$a"
            nix run nixpkgs#nix-update -- \
              --flake --use-update-script --commit \
              "legacyPackages.aarch64-linux.$a" \
              || echo "::warning::no update or update failed for $a"
            echo "::endgroup::"
          done
      - name: Create PR
        uses: peter-evans/create-pull-request@v6
        with:
          token: ${{ secrets.GH_TOKEN_FOR_UPDATES }}
          branch: update-packages
          delete-branch: true
          title: "Update packages"
          labels: |
            dependencies
            automated
          body: |
            Automated package bumps via nix-update. Built by buildbot-nix on aarch64.
```

- [ ] **Step 4: Verify the docs render and workflow parses**

```bash
git add docs/version-pins.md docs/external-dependencies.md .github/workflows/update-packages.yml
nix run nixpkgs#yamllint -- -d relaxed .github/workflows/update-packages.yml
grep -c "kernel-rk3326" docs/external-dependencies.md
```

Expected: yamllint passes (no errors); `grep -c kernel-rk3326` prints `0`.

- [ ] **Step 5: Commit**

```bash
git commit -m "docs: add version pin inventory and bump workflow

Foundational commit for #47: pin inventory, refreshed external-dependencies
reference, and the scheduled nix-update workflow. Per-package updateScripts
land in following commits."
```

---

### Task 2: flycast2021 updateScript

**Files:**
- Modify: `pkgs/flycast2021/default.nix`

**Interfaces:**
- Consumes: `nix-update-script` from callPackage (auto-provided by the overlay's `callPackage`).
- Produces: `legacyPackages.aarch64-linux.flycast2021.updateScript`.

- [ ] **Step 1: Add the input**

In `pkgs/flycast2021/default.nix`, add `nix-update-script,` to the argument set (after `fetchpatch,`):

```nix
{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchpatch,
  nix-update-script,
  libGL,
  zlib,
}:
```

- [ ] **Step 2: Add `passthru.updateScript`**

This package is `stdenv.mkDerivation { ... }` (no `finalAttrs`, no existing `passthru`). Add a `passthru` block before the closing `}` of the derivation (e.g. after `meta`/`enableParallelBuilding`). Insert:

```nix
  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--version=branch"
    ];
  };
```

- [ ] **Step 3: Verify the updateScript evaluates**

```bash
nix eval --json .#legacyPackages.aarch64-linux.flycast2021.updateScript
```

Expected: a JSON array whose first element is a `/nix/store/...-nix-update` path, followed by `"--flake"` and `"--version=branch"`.

- [ ] **Step 4: Dry-run nix-update (hash refresh only, no version change)**

```bash
nix run nixpkgs#nix-update -- --flake --version=skip legacyPackages.aarch64-linux.flycast2021
git diff --stat
```

Expected: command exits 0. If the pin is current, no diff. If `git diff` shows a hash change, revert it (`git checkout pkgs/flycast2021/default.nix`) — this task adds machinery only, it does not bump pins.

- [ ] **Step 5: Commit**

```bash
git add pkgs/flycast2021/default.nix
git commit -m "chore(flycast2021): add nix-update updateScript"
```

---

### Task 3: emulationstation-fcamod updateScript

**Files:**
- Modify: `pkgs/emulationstation-fcamod/default.nix`

**Interfaces:**
- Produces: `legacyPackages.aarch64-linux.emulationstation-fcamod.updateScript`.

- [ ] **Step 1: Add the input**

Add `nix-update-script,` to the argument set (e.g. after `fetchFromGitHub,`):

```nix
{
  lib,
  stdenv,
  fetchFromGitHub,
  nix-update-script,
  writeShellScript,
  ...
```

- [ ] **Step 2: Add `passthru.updateScript`**

This package is `stdenv.mkDerivation { ... }` with a `let ... in` prelude and no existing `passthru`. Add before the derivation's closing `}`:

```nix
  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--version=branch=351v"
    ];
  };
```

The `351v` branch is the fcamod fork branch this package tracks (see CLAUDE.md: ES-fcamod 351v branch). `fetchSubmodules = true` is already set; nix-update recomputes the submodule-inclusive hash.

- [ ] **Step 3: Verify the updateScript evaluates**

```bash
nix eval --json .#legacyPackages.aarch64-linux.emulationstation-fcamod.updateScript
```

Expected: JSON array ending in `"--flake"`, `"--version=branch=351v"`.

- [ ] **Step 4: Dry-run nix-update**

```bash
nix run nixpkgs#nix-update -- --flake --version=skip legacyPackages.aarch64-linux.emulationstation-fcamod
git diff --stat
```

Expected: exits 0. Revert any hash change (`git checkout pkgs/emulationstation-fcamod/default.nix`).

- [ ] **Step 5: Commit**

```bash
git add pkgs/emulationstation-fcamod/default.nix
git commit -m "chore(emulationstation-fcamod): add nix-update updateScript"
```

---

### Task 4: gptokeyb2 updateScript

**Files:**
- Modify: `pkgs/gptokeyb2/default.nix`

**Interfaces:**
- Produces: `legacyPackages.aarch64-linux.gptokeyb2.updateScript`.

- [ ] **Step 1: Add the input**

```nix
{
  lib,
  stdenv,
  fetchFromGitHub,
  nix-update-script,
  cmake,
  SDL2,
  libevdev,
}:
```

- [ ] **Step 2: Add `passthru.updateScript`**

This package is `stdenv.mkDerivation (finalAttrs: { ... })` with no existing `passthru`. Add before the closing `})`:

```nix
  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--version=branch"
    ];
  };
```

Note: the current `version` is `0.2.0-unstable-2025-09-22`; `--version=branch` will rewrite it to `0-unstable-<date>` on the next real bump (the `0.2.0` prefix is dropped). This is cosmetic and acceptable.

- [ ] **Step 3: Verify the updateScript evaluates**

```bash
nix eval --json .#legacyPackages.aarch64-linux.gptokeyb2.updateScript
```

Expected: JSON array ending in `"--flake"`, `"--version=branch"`.

- [ ] **Step 4: Dry-run nix-update**

```bash
nix run nixpkgs#nix-update -- --flake --version=skip legacyPackages.aarch64-linux.gptokeyb2
git diff --stat
```

Expected: exits 0. Revert any hash change.

- [ ] **Step 5: Commit**

```bash
git add pkgs/gptokeyb2/default.nix
git commit -m "chore(gptokeyb2): add nix-update updateScript"
```

---

### Task 5: es-theme-gbz35-mod updateScript (needs a version attr)

**Files:**
- Modify: `pkgs/es-theme-gbz35-mod/default.nix`

**Interfaces:**
- Produces: `legacyPackages.aarch64-linux.es-theme-gbz35-mod.{version,updateScript}`.

This package is a bare `fetchFromGitHub { ... }` with no `version`. `nix-update` needs a `version` attribute to rewrite, so we add `passthru.version`. Confirmed: `passthru` attrs surface as top-level derivation attrs here (`.themeName` resolves), so `passthru.version` becomes `.version`.

- [ ] **Step 1: Add the input**

```nix
{
  lib,
  fetchFromGitHub,
  nix-update-script,
}:
```

- [ ] **Step 2: Add `version` and `updateScript` to the existing `passthru`**

Replace the existing `passthru.themeName = "gbz35_mod";` line with a `passthru` block:

```nix
  passthru = {
    themeName = "gbz35_mod";
    version = "0-unstable-2026-04-12";
    updateScript = nix-update-script {
      extraArgs = [
        "--flake"
        "--version=branch"
      ];
    };
  };
```

- [ ] **Step 3: Verify both attrs resolve**

```bash
nix eval --raw .#legacyPackages.aarch64-linux.es-theme-gbz35-mod.version
nix eval --json .#legacyPackages.aarch64-linux.es-theme-gbz35-mod.updateScript
```

Expected: prints `0-unstable-2026-04-12`; then a JSON array ending in `"--flake"`, `"--version=branch"`.

- [ ] **Step 4: Dry-run nix-update (real branch update on a throwaway, then revert)**

`--version=skip` only refreshes the src hash, which won't exercise the version rewrite. Run a real branch update and then revert, to confirm nix-update can rewrite both `rev`/`hash` and the new `version`:

```bash
nix run nixpkgs#nix-update -- --flake --version=branch legacyPackages.aarch64-linux.es-theme-gbz35-mod
git diff pkgs/es-theme-gbz35-mod/default.nix
```

Expected: the diff shows `rev`, `hash`, and `version` updated to a new `0-unstable-<date>` with no eval errors. **Then revert the pin bump** (machinery-only commit):

```bash
git checkout pkgs/es-theme-gbz35-mod/default.nix
```

Re-apply only the Step 1–2 edits (input + passthru block) if the checkout reverted them — i.e. ensure the file has the new `passthru` block but the original `rev`/`hash`/`version` placeholder. Confirm:

```bash
git diff pkgs/es-theme-gbz35-mod/default.nix   # shows only the added input + passthru block
```

Fallback if `nix-update --version=branch` errors on this package (e.g. cannot locate the version string to rewrite): replace `passthru.updateScript` with a self-contained script instead —

```nix
    updateScript = lib.getExe (writeShellApplication {
      name = "update-es-theme-gbz35-mod";
      runtimeInputs = [ git nurl gnused coreutils ];
      text = ''
        rev=$(git ls-remote https://github.com/Jetup13/es-theme-gbz35_mod HEAD | cut -f1)
        hash=$(nurl --hash https://github.com/Jetup13/es-theme-gbz35_mod "$rev")
        date=$(date +%Y-%m-%d)
        f=pkgs/es-theme-gbz35-mod/default.nix
        sed -i "s|rev = \".*\";|rev = \"$rev\";|" "$f"
        sed -i "s|hash = \".*\";|hash = \"$hash\";|" "$f"
        sed -i "s|version = \".*\";|version = \"0-unstable-$date\";|" "$f"
      '';
    });
```

(This fallback needs `writeShellApplication, git, nurl, gnused, coreutils` added to the inputs.) Prefer the `nix-update-script` form; use the fallback only if Step 4 fails.

- [ ] **Step 5: Commit**

```bash
git add pkgs/es-theme-gbz35-mod/default.nix
git commit -m "chore(es-theme-gbz35-mod): add version attr and nix-update updateScript"
```

---

### Task 6: SDL2_classic updateScript (regex-pinned to 2.x)

**Files:**
- Modify: `pkgs/SDL2_classic/default.nix`

**Interfaces:**
- Produces: `legacyPackages.aarch64-linux.SDL2_classic.updateScript`.

`SDL2_classic` tracks `release-2.32.6` and MUST stay on 2.x. A bare release-tracking update would jump to SDL3, so the version is constrained by regex to `release-2.*`.

- [ ] **Step 1: Add the input**

```nix
{
  lib,
  stdenv,
  fetchFromGitHub,
  nix-update-script,
  pkg-config,
  ...
```

- [ ] **Step 2: Add `passthru.updateScript`**

This package is `stdenv.mkDerivation (finalAttrs: { ... })`. Add a `passthru` block before the closing `})` (after `meta` if present):

```nix
  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--version-regex"
      "release-2\\.(.*)"
    ];
  };
```

Note: the rev is `release-${finalAttrs.version}` and `version = "2.32.6"`. `nix-update` with `--version-regex 'release-2\.(.*)'` considers only `release-2.*` tags, so it stays within the 2.x series.

- [ ] **Step 3: Verify the updateScript evaluates**

```bash
nix eval --json .#legacyPackages.aarch64-linux.SDL2_classic.updateScript
```

Expected: JSON array ending in `"--flake"`, `"--version-regex"`, `"release-2\\.(.*)"`.

- [ ] **Step 4: Dry-run nix-update and confirm it stays on 2.x**

```bash
nix run nixpkgs#nix-update -- --flake --version-regex 'release-2\.(.*)' legacyPackages.aarch64-linux.SDL2_classic
git diff pkgs/SDL2_classic/default.nix
```

Expected: either no change, or a bump to a later `2.x` version (NOT 3.x). If the diff shows a `3.` version or `release-3`, the regex is wrong — stop and fix. **Revert any pin change** afterward:

```bash
git checkout pkgs/SDL2_classic/default.nix
```

Re-apply only the Step 1–2 edits if needed; confirm the diff shows only the input + passthru block.

- [ ] **Step 5: Commit**

```bash
git add pkgs/SDL2_classic/default.nix
git commit -m "chore(SDL2_classic): add nix-update updateScript pinned to 2.x"
```

---

### Task 7: linux-h700 coupled updater

**Files:**
- Create: `pkgs/linux-h700/update.sh`
- Modify: `pkgs/linux-h700/default.nix`

**Interfaces:**
- Consumes: `nix-update-script` is NOT used here (custom script). Adds inputs `writeShellApplication, git, nurl, curl, jq, gnused, gnugrep, gawk, coreutils, nix` for the wrapper.
- Produces: `legacyPackages.aarch64-linux.linux-h700.updateScript` (a single-element list `[ "<store path>/bin/update-linux-h700" ]`).

The updater bumps the ROCKNIX `distribution` rev, derives the kernel version from `package.mk`, recomputes both hashes, rewrites all four pinned values, and fails on patch-list drift.

- [ ] **Step 1: Write the updater script**

Create `pkgs/linux-h700/update.sh`:

```bash
#!/usr/bin/env bash
# Bump the ROCKNIX distribution rev and the coupled kernel version+hash for
# pkgs/linux-h700. Run via `passthru.updateScript`; assumes CWD is the repo root.
set -euo pipefail

ROCKNIX_BRANCH="${ROCKNIX_BRANCH:-main}"
NIXFILE="pkgs/linux-h700/default.nix"
OWNER_REPO="ROCKNIX/distribution"
PATCH_DIR="projects/ROCKNIX/devices/H700/patches/linux"

dryrun=0
[ "${1:-}" = "--dry-run" ] && dryrun=1

echo "Resolving latest ROCKNIX rev on $ROCKNIX_BRANCH..."
new_rev=$(git ls-remote "https://github.com/$OWNER_REPO" "refs/heads/$ROCKNIX_BRANCH" | cut -f1)
[ -n "$new_rev" ] || { echo "ERROR: could not resolve ROCKNIX rev"; exit 1; }
echo "  rev: $new_rev"

echo "Parsing H700 PKG_VERSION from package.mk..."
pkgmk="https://raw.githubusercontent.com/$OWNER_REPO/$new_rev/projects/ROCKNIX/packages/linux/package.mk"
new_version=$(curl -fsSL "$pkgmk" | awk '
  /^[[:space:]]*[A-Z0-9|]*H700[A-Z0-9|]*\)/ { f=1 }
  f && /PKG_VERSION=/ { gsub(/.*PKG_VERSION="|".*/, ""); print; exit }
')
[ -n "$new_version" ] || { echo "ERROR: could not parse PKG_VERSION"; exit 1; }
echo "  kernel version: $new_version"

echo "Computing kernel tarball hash..."
major="${new_version%%.*}"
kurl="https://cdn.kernel.org/pub/linux/kernel/v${major}.x/linux-${new_version}.tar.xz"
kern_b32=$(nix-prefetch-url "$kurl")
kern_hash=$(nix hash to-sri --type sha256 "$kern_b32")
echo "  kernel hash: $kern_hash"

echo "Computing ROCKNIX sparseCheckout hash..."
patch_hash=$(nix build --impure --no-link --print-out-paths --expr "
  (import <nixpkgs> {}).fetchFromGitHub {
    owner = \"ROCKNIX\"; repo = \"distribution\"; rev = \"$new_rev\";
    sparseCheckout = [ \"$PATCH_DIR\" ];
    hash = \"\";
  }" 2>&1 | grep -oP 'got:\s+\K\S+') || true
[ -n "$patch_hash" ] || { echo "ERROR: could not compute sparseCheckout hash"; exit 1; }
echo "  patches hash: $patch_hash"

echo "Checking patch-list drift..."
remote_patches=$(curl -fsSL \
  "https://api.github.com/repos/$OWNER_REPO/contents/$PATCH_DIR?ref=$new_rev" \
  | jq -r '.[].name' | grep '\.patch$' | sort)
current_patches=$(grep -oP '"\K[^"]+\.patch(?=")' "$NIXFILE" | sort -u)
if [ "$remote_patches" != "$current_patches" ]; then
  echo "ERROR: patch-list drift — upstream patch files differ from the patches array in $NIXFILE"
  echo "--- upstream ($new_rev) ---"; echo "$remote_patches"
  echo "--- current $NIXFILE ---"; echo "$current_patches"
  echo "Reconcile the patches array by hand before bumping."
  exit 1
fi
echo "  no drift."

if [ "$dryrun" = 1 ]; then
  echo "DRY RUN — would set rev=$new_rev version=$new_version"
  echo "  kernel hash=$kern_hash  patches hash=$patch_hash"
  exit 0
fi

echo "Rewriting $NIXFILE..."
sed -i "s|version = \"[^\"]*\";|version = \"$new_version\";|" "$NIXFILE"
sed -i "s|modDirVersion = \"[^\"]*\";|modDirVersion = \"$new_version\";|" "$NIXFILE"
sed -i "s|rev = \"[0-9a-f]\{40\}\";|rev = \"$new_rev\";|" "$NIXFILE"
# kernel tarball hash (the fetchurl block) and patches hash (the fetchFromGitHub
# block) are the two sha256- lines; rewrite by their surrounding context.
sed -i "/url = \"mirror:\/\/kernel/,/hash = / s|hash = \"sha256-[^\"]*\";|hash = \"$kern_hash\";|" "$NIXFILE"
sed -i "/sparseCheckout/,/hash = / s|hash = \"sha256-[^\"]*\";|hash = \"$patch_hash\";|" "$NIXFILE"
echo "Done."
```

Note on hash rewriting: the script targets the kernel hash within the
`url = "mirror://kernel...` → `hash =` range, and the patches hash within the
`sparseCheckout` → `hash =` range, so the two `sha256-` lines are not confused.
Verify these ranges match `default.nix` structure (kernel `fetchurl` block lines
~21-24; `rocknixPatches` `fetchFromGitHub` block lines ~27-33).

- [ ] **Step 2: Add inputs and `passthru.updateScript` to `default.nix`**

Add to the argument set at the top of `pkgs/linux-h700/default.nix` (after the existing inputs, before `...`):

```nix
{
  lib,
  fetchFromGitHub,
  fetchurl,
  linuxManualConfig,
  stdenv,
  flex,
  bison,
  perl,
  runCommand,
  rg28xx-panel-firmware,
  writeShellApplication,
  git,
  nurl,
  curl,
  jq,
  gnused,
  gnugrep,
  gawk,
  coreutils,
  nix,
  ...
}:
```

In the `let` block, define the updater before the final `in`:

```nix
  updateScript = writeShellApplication {
    name = "update-linux-h700";
    runtimeInputs = [
      git
      nurl
      curl
      jq
      gnused
      gnugrep
      gawk
      coreutils
      nix
    ];
    text = builtins.readFile ./update.sh;
  };
```

Then attach it in the final `.overrideAttrs` `passthru` block. The file currently ends:

```nix
  (linuxManualConfig {
    ...
  }).overrideAttrs
    (old: {
      passthru = (old.passthru or { }) // {
        features = { };
      };
    })
```

Change the `passthru` merge to add `updateScript`:

```nix
      passthru = (old.passthru or { }) // {
        features = { };
        updateScript = [ (lib.getExe updateScript) ];
      };
```

(`nurl` is referenced in `runtimeInputs` even though `update.sh` uses
`nix build` for the sparseCheckout hash; keep it available for manual use. If
unused it can be dropped — verify with `shellcheck` in Step 3.)

- [ ] **Step 3: Verify eval and shell sanity**

```bash
git add pkgs/linux-h700/update.sh pkgs/linux-h700/default.nix
nix eval --json .#legacyPackages.aarch64-linux.linux-h700.updateScript
nix run nixpkgs#shellcheck -- pkgs/linux-h700/update.sh
```

Expected: `updateScript` is a one-element JSON array with a `/nix/store/...-update-linux-h700/bin/update-linux-h700` path; shellcheck reports no errors (warnings acceptable).

- [ ] **Step 4: Dry-run the updater against current pins**

```bash
nix build --no-link .#legacyPackages.aarch64-linux.linux-h700.updateScript
SCRIPT=$(nix eval --raw .#legacyPackages.aarch64-linux.linux-h700.updateScript --apply 'x: builtins.head x')
"$SCRIPT" --dry-run
```

Expected: prints the resolved rev, kernel version (today: `7.0.11` if `main` still targets it — or a newer value if ROCKNIX moved), both computed hashes, and "no drift." Must exit 0. If it reports patch drift, that is the script working as intended — note the drift; do not auto-reconcile in this task.

- [ ] **Step 5: Commit**

```bash
git add pkgs/linux-h700/update.sh pkgs/linux-h700/default.nix
git commit -m "feat(linux-h700): add coupled ROCKNIX/kernel updater

update.sh bumps the ROCKNIX rev, derives the kernel version from package.mk,
recomputes both hashes, and fails on patch-list drift."
```

---

### Task 8: Final verification

**Files:** none (verification only)

- [ ] **Step 1: Confirm the flake evaluates and all six updateScripts resolve**

```bash
for a in flycast2021 emulationstation-fcamod gptokeyb2 es-theme-gbz35-mod SDL2_classic linux-h700; do
  echo -n "$a: "
  nix eval --json ".#legacyPackages.aarch64-linux.$a.updateScript" >/dev/null && echo OK || echo FAIL
done
```

Expected: all six print `OK`.

- [ ] **Step 2: Confirm treefmt is clean (repo formatter)**

```bash
nix fmt -- --fail-on-change 2>&1 | tail -5
```

Expected: no formatting changes. If it reformats, `git add -u && git commit --amend --no-edit` the affected per-package commit, or commit the formatting fix.

- [ ] **Step 3: Confirm the working tree has no stray pin changes**

```bash
git log --oneline main..HEAD
git diff main --stat
```

Expected: 7 commits (1 foundational + 6 package); the diff touches only `docs/`, `.github/workflows/`, and the six package files — no `rev`/`hash`/`version` value changes beyond the es-theme `version` attr addition and the new `update.sh`.

---

## Self-Review

**Spec coverage:**
- "Enumerate in one place" → Task 1 `docs/version-pins.md`. ✓
- Refresh stale `external-dependencies.md` → Task 1 Step 2. ✓
- Scripted tier updateScripts → Tasks 2–6. ✓
- linux-h700 custom updater + coupling + patch-drift → Task 7. ✓
- Inline workflow, combined PR, buildbot gate → Task 1 Step 3. ✓
- Manual tier documented, not automated → Task 1 inventory. ✓
- `libmali`/`mali-kbase` manual → Task 1 inventory. ✓
- Commit structure (foundational + per package) → task boundaries. ✓

**Placeholder scan:** no TBD/TODO; every code step shows full content; the es-theme fallback is fully spelled out. ✓

**Type/name consistency:** allowlist string identical in workflow (Task 1) and final check (Task 8); `nix-update-script { extraArgs = [...]; }` form consistent across Tasks 2–6; `updateScript` is a list everywhere (matching `nix-update-script`'s return and the linux-h700 `[ (lib.getExe …) ]`). ✓

**Known runtime-verification points (carried from the spec, each has a test step):**
1. es-theme `version`-attr rewrite by nix-update → Task 5 Step 4 (with fallback).
2. CI `--use-update-script` + `<nixpkgs>` resolution → exercised first by the scheduled workflow / `workflow_dispatch`; the local dry-runs use the inner flags directly so they don't depend on it.
