#!/usr/bin/env bash
# Bump the ROCKNIX distribution rev and the coupled kernel version+hash for
# pkgs/linux-h700. The kernel version is dictated by ROCKNIX's package.mk H700
# case, so the two move as a pair. Run via passthru.updateScript; assumes CWD is
# the repo root. Pass --dry-run to print the resolved values without writing.
set -euo pipefail

ROCKNIX_BRANCH="${ROCKNIX_BRANCH:-next}"
NIXFILE="pkgs/linux-h700/default.nix"
OWNER_REPO="ROCKNIX/distribution"
PATCH_DIR="projects/ROCKNIX/devices/H700/patches/linux"
FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

dryrun=0
[ "${1:-}" = "--dry-run" ] && dryrun=1

echo "Resolving latest ROCKNIX rev on $ROCKNIX_BRANCH..."
new_rev=$(git ls-remote "https://github.com/$OWNER_REPO" "refs/heads/$ROCKNIX_BRANCH" | cut -f1)
[ -n "$new_rev" ] || { echo "ERROR: could not resolve ROCKNIX rev"; exit 1; }
echo "  rev: $new_rev"

echo "Parsing H700 PKG_VERSION from package.mk..."
pkgmk="https://raw.githubusercontent.com/$OWNER_REPO/$new_rev/projects/ROCKNIX/packages/linux/package.mk"
pkgmk_content=$(curl -fsSL "$pkgmk")
new_version=$(awk '
  /^[[:space:]]*[A-Z0-9|]*H700[A-Z0-9|]*\)/ { f=1 }
  f == 1 && /PKG_VERSION=/ { gsub(/.*PKG_VERSION="|".*/, ""); print; f=2 }
' <<< "$pkgmk_content")
[ -n "$new_version" ] || { echo "ERROR: could not parse PKG_VERSION"; exit 1; }
major="${new_version%%.*}"
echo "  kernel version: $new_version (v${major}.x)"

echo "Computing kernel tarball hash..."
kurl="https://cdn.kernel.org/pub/linux/kernel/v${major}.x/linux-${new_version}.tar.xz"
kern_b32=$(nix-prefetch-url "$kurl")
kern_hash=$(nix hash convert --hash-algo sha256 "$kern_b32")
echo "  kernel hash: $kern_hash"

echo "Computing ROCKNIX sparseCheckout hash..."
patch_hash=$(nix build --impure --no-link --print-out-paths --expr "
  (import <nixpkgs> { }).fetchFromGitHub {
    owner = \"ROCKNIX\";
    repo = \"distribution\";
    rev = \"$new_rev\";
    sparseCheckout = [ \"$PATCH_DIR\" ];
    hash = \"$FAKE_HASH\";
  }" 2>&1 | grep -oP 'got:\s+\K\S+') || true
[ -n "$patch_hash" ] || { echo "ERROR: could not compute sparseCheckout hash"; exit 1; }
echo "  patches hash: $patch_hash"

echo "Checking patch-list drift..."
# The patches array is a curated subset of the upstream patch dir (some upstream
# patches are deliberately not applied). Hard-fail only when a patch we DO apply
# has disappeared upstream (the build would break); upstream additions we don't
# apply are informational.
remote_patches=$(curl -fsSL \
  "https://api.github.com/repos/$OWNER_REPO/contents/$PATCH_DIR?ref=$new_rev" \
  | grep -oP '"name":\s*"\K[^"]+\.patch' | sort)
current_patches=$(grep -oP '"\K[^"]+\.patch(?=")' "$NIXFILE" | sort -u)
missing=$(comm -23 <(echo "$current_patches") <(echo "$remote_patches"))
if [ -n "$missing" ]; then
  echo "ERROR: patches applied in $NIXFILE no longer exist at $new_rev:"
  echo "$missing"
  echo "Reconcile the patches array by hand before bumping."
  exit 1
fi
added=$(comm -13 <(echo "$current_patches") <(echo "$remote_patches"))
if [ -n "$added" ]; then
  echo "NOTE: upstream has patches not applied here (curated subset):"
  echo "$added"
fi
echo "  patch check OK."

if [ "$dryrun" = 1 ]; then
  echo "DRY RUN — would set:"
  echo "  rev          = $new_rev"
  echo "  version      = $new_version"
  echo "  kernel hash  = $kern_hash"
  echo "  patches hash = $patch_hash"
  exit 0
fi

echo "Rewriting $NIXFILE..."
sed -i "s|version = \"[^\"]*\";|version = \"$new_version\";|" "$NIXFILE"
sed -i "s|modDirVersion = \"[^\"]*\";|modDirVersion = \"$new_version\";|" "$NIXFILE"
sed -i "s|rev = \"[0-9a-f]\{40\}\";|rev = \"$new_rev\";|" "$NIXFILE"
sed -i "s|kernel/v[0-9]*\.x/|kernel/v${major}.x/|" "$NIXFILE"
# Two sha256- lines: the kernel tarball (inside the mirror:// fetchurl block)
# and the patches (inside the sparseCheckout fetchFromGitHub block). Scope each
# rewrite to its surrounding context so they are not confused.
sed -i "/url = \"mirror:\/\/kernel/,/hash = / s|hash = \"sha256-[^\"]*\";|hash = \"$kern_hash\";|" "$NIXFILE"
sed -i "/sparseCheckout/,/hash = / s|hash = \"sha256-[^\"]*\";|hash = \"$patch_hash\";|" "$NIXFILE"
echo "Done."
