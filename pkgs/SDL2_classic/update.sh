#!/usr/bin/env nix-shell
#!nix-shell -i bash -p git nurl gnused gnugrep coreutils
set -euo pipefail

url=https://github.com/libsdl-org/SDL
f=pkgs/SDL2_classic/default.nix
version=$(git ls-remote --tags --refs "$url" 'release-2.*' | sed 's|.*refs/tags/release-||' | sort -V | tail -1)
if grep -q "version = \"$version\";" "$f"; then
  exit 0
fi
hash=$(nurl "$url" "release-$version" -H)
sed -i "s|version = \"[^\"]*\";|version = \"$version\";|" "$f"
sed -i "s|hash = \"sha256-[^\"]*\";|hash = \"$hash\";|" "$f"
