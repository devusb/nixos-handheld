#!/usr/bin/env nix-shell
#!nix-shell -i bash -p git curl jq gnused gnugrep gawk coreutils
# Bump pkgs/linux-h700 to the latest ROCKNIX rev: the rev and its hash, the
# kernel version and tarball hash from ROCKNIX's package.mk H700 case, and the
# version-specific patch directories that case applies. Assumes CWD is the repo
# root. Pass --dry-run to print the resolved values without writing.
set -euo pipefail

ROCKNIX_BRANCH="${ROCKNIX_BRANCH:-next}"
NIXFILE="${NIXFILE:-pkgs/linux-h700/default.nix}"
OWNER_REPO="ROCKNIX/distribution"
LINUX_PKG="projects/ROCKNIX/packages/linux"
H700_PATCHES="projects/ROCKNIX/devices/H700/patches/linux"
# shellcheck disable=SC2016
EXPECTED_PATCH_DIRS='PKG_PATCH_DIRS="${LINUX} mainline ${DEVICE} default"'
FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

dryrun=0
[ "${1:-}" = "--dry-run" ] && dryrun=1

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

gh_api() {
  local auth=()
  [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  curl -fsSL "${auth[@]}" "https://api.github.com/repos/$OWNER_REPO/$1"
}

# Names of entries of the given type ("file" or "dir") in a repo directory.
list_dir() {
  local path="$1" rev="$2" type="$3"
  gh_api "contents/$path?ref=$rev" | jq -r --arg t "$type" '.[] | select(.type == $t) | .name'
}

old_rev=$(grep -oP 'rev = "\K[0-9a-f]{40}(?=";)' "$NIXFILE")
old_version=$(grep -oP '^\s*version = "\K[^"]+' "$NIXFILE")
old_version_dirs=$(awk '/versionPatchDirs = \[/ { f = 1 } f { print } f && /\];/ { exit }' "$NIXFILE" | grep -o '"[^"]*"' | tr -d '"' || true)

echo "Resolving latest ROCKNIX rev on $ROCKNIX_BRANCH..."
new_rev=$(git ls-remote "https://github.com/$OWNER_REPO" "refs/heads/$ROCKNIX_BRANCH" | cut -f1)
[ -n "$new_rev" ] || fail "could not resolve ROCKNIX rev"
echo "  rev: $old_rev -> $new_rev"
if [ "$new_rev" = "$old_rev" ]; then
  echo "Already up to date."
  exit 0
fi

echo "Parsing the H700 case of package.mk..."
pkgmk=$(curl -fsSL "https://raw.githubusercontent.com/$OWNER_REPO/$new_rev/$LINUX_PKG/package.mk")
grep -qxF "$EXPECTED_PATCH_DIRS" <<<"$pkgmk" \
  || fail "package.mk no longer sets $EXPECTED_PATCH_DIRS; review patchDirs in $NIXFILE"
h700_case=$(awk '
  /^[[:space:]]*[A-Z0-9|]*H700[A-Z0-9|]*\)/ { f=1 }
  f && !/^[[:space:]]*#/ { print }
  f && /;;/ { exit }
' <<<"$pkgmk")
[ -n "$h700_case" ] || fail "no H700 case in package.mk"
grep -q 'PKG_PATCH_DIRS=' <<<"$h700_case" \
  && fail "the H700 case replaces PKG_PATCH_DIRS; review patchDirs in $NIXFILE"
new_version=$(grep -oP 'PKG_VERSION="\K[^"]+' <<<"$h700_case") || fail "no PKG_VERSION in the H700 case"
extra_dirs=$(grep -oP 'PKG_PATCH_DIRS\+="\K[^"]+' <<<"$h700_case" | tr ' ' '\n' | sed '/^$/d' || true)
major="${new_version%%.*}"
case "$new_version" in
  *.*.*) new_mod_dir_version="$new_version" ;;
  *) new_mod_dir_version="$new_version.0" ;;
esac
echo "  kernel version: $old_version -> $new_version (modDirVersion $new_mod_dir_version)"

echo "Resolving version patch directories..."
patch_dirs_available=$(list_dir "$LINUX_PKG/patches" "$new_rev" dir)
[ -n "$(list_dir "$LINUX_PKG/patches" "$new_rev" file | grep '\.patch$' || true)" ] \
  && fail "package.mk has top-level patches; review patchDirs in $NIXFILE"
for d in aarch64 H700 default rocknix-joypad; do
  grep -qxF "$d" <<<"$patch_dirs_available" \
    && fail "package.mk has a $d patch directory; review patchDirs in $NIXFILE"
done
new_version_dirs=$(
  {
    echo "$extra_dirs"
    if grep -qxF "$new_version" <<<"$patch_dirs_available"; then echo "$new_version"; fi
  } | sed '/^$/d' | awk '!seen[$0]++'
)
for d in $new_version_dirs; do
  grep -qxF "$d" <<<"$patch_dirs_available" || fail "patch directory $d does not exist at $new_rev"
done
applied_dirs=("$LINUX_PKG/patches/mainline" "$H700_PATCHES")
for d in $new_version_dirs; do applied_dirs+=("$LINUX_PKG/patches/$d"); done
for d in "${applied_dirs[@]}"; do
  [ -z "$(list_dir "$d" "$new_rev" dir)" ] \
    || fail "$d has subdirectories; review patchDirs in $NIXFILE"
done
echo "  versionPatchDirs: [ $(tr '\n' ' ' <<<"$old_version_dirs")] -> [ $(tr '\n' ' ' <<<"$new_version_dirs")]"

if [ "$new_version" != "$old_version" ]; then
  echo "Computing kernel tarball hash..."
  kern_b32=$(nix-prefetch-url "https://cdn.kernel.org/pub/linux/kernel/v${major}.x/linux-${new_version}.tar.xz")
  kern_hash=$(nix hash convert --hash-algo sha256 "$kern_b32")
  echo "  kernel hash: $kern_hash"
fi

echo "Computing ROCKNIX sparseCheckout hash..."
sparse=$(sed -n '/sparseCheckout = \[/,/\];/p' "$NIXFILE" | grep -oP '"\K[^"]+' | sed 's/.*/"&"/' | tr '\n' ' ')
[ -n "$sparse" ] || fail "could not read sparseCheckout from $NIXFILE"
patch_hash=$(nix build --impure --no-link --expr "
  (builtins.getFlake \"git+file://$PWD\").legacyPackages.\${builtins.currentSystem}.fetchFromGitHub {
    owner = \"ROCKNIX\";
    repo = \"distribution\";
    rev = \"$new_rev\";
    sparseCheckout = [ $sparse ];
    hash = \"$FAKE_HASH\";
  }" 2>&1 | grep -oP 'got:\s+\K\S+' || true)
[ -n "$patch_hash" ] || fail "could not compute sparseCheckout hash"
echo "  sparseCheckout hash: $patch_hash"

# Every patch applied at a rev, as "<dir>/<file>".
applied_patches() {
  local rev="$1" dirs="$2" d
  for d in mainline $dirs; do
    list_dir "$LINUX_PKG/patches/$d" "$rev" file | grep '\.patch$' | sed "s|^|$d/|" || true
  done
  list_dir "$H700_PATCHES" "$rev" file | grep '\.patch$' | sed "s|^|H700/|" || true
}
echo "Patch changes:"
comm -3 \
  <(applied_patches "$old_rev" "$old_version_dirs" | sort) \
  <(applied_patches "$new_rev" "$new_version_dirs" | sort) \
  | sed -e 's/^\t/  + /' -e 't' -e 's/^/  - /'

if [ "$dryrun" = 1 ]; then
  echo "Dry run; $NIXFILE not changed."
  exit 0
fi

echo "Rewriting $NIXFILE..."
sed -i \
  -e "s|^\(\s*\)version = \"[^\"]*\";|\1version = \"$new_version\";|" \
  -e "s|modDirVersion = \"[^\"]*\";|modDirVersion = \"$new_mod_dir_version\";|" \
  -e "s|rev = \"[0-9a-f]\{40\}\";|rev = \"$new_rev\";|" \
  -e "/sparseCheckout = \[/,/hash = / s|hash = \"sha256-[^\"]*\";|hash = \"$patch_hash\";|" \
  "$NIXFILE"
# Writes versionPatchDirs the way nixfmt formats it.
awk -v dirs="$(tr '\n' ' ' <<<"$new_version_dirs")" '
  /^[[:space:]]*versionPatchDirs = \[/ {
    indent = $0; sub(/[^[:space:]].*/, "", indent)
    n = split(dirs, d, " ")
    if (n == 1) print indent "versionPatchDirs = [ \"" d[1] "\" ];"
    else {
      print indent "versionPatchDirs = ["
      for (i = 1; i <= n; i++) print indent "  \"" d[i] "\""
      print indent "];"
    }
    skip = 1
  }
  skip { if (/\];/) skip = 0; next }
  { print }
' "$NIXFILE" >"$NIXFILE.tmp" && mv "$NIXFILE.tmp" "$NIXFILE"
if [ "$new_version" != "$old_version" ]; then
  sed -i \
    -e "s|kernel/v[0-9]*\.x/|kernel/v${major}.x/|" \
    -e "/url = \"mirror:\/\/kernel/,/hash = / s|hash = \"sha256-[^\"]*\";|hash = \"$kern_hash\";|" \
    "$NIXFILE"
fi
echo "Done."
