{
  lib,
  fetchFromGitHub,
  writeShellApplication,
  git,
  nurl,
  gnused,
  coreutils,
}:

fetchFromGitHub {
  owner = "Jetup13";
  repo = "es-theme-gbz35_mod";
  rev = "4605d6805c2a24cadffe5a331868da4f8ddbe1df";
  hash = "sha256-c9Ycnb5Etc7GaNyPhq1qiSH0l4IA6vh1/Cn17eTlWI4=";

  passthru = {
    themeName = "gbz35_mod";
    version = "0-unstable-2021-09-19";
    # Bare fetchFromGitHub has no `src`, so nix-update can't drive it; this
    # script bumps rev/hash/version directly.
    updateScript = [
      (lib.getExe (writeShellApplication {
        name = "update-es-theme-gbz35-mod";
        runtimeInputs = [
          git
          nurl
          gnused
          coreutils
        ];
        text = ''
          url=https://github.com/Jetup13/es-theme-gbz35_mod
          rev=$(git ls-remote "$url" HEAD | cut -f1)
          hash=$(nurl "$url" "$rev" -H)
          date=$(date +%Y-%m-%d)
          f=pkgs/es-theme-gbz35-mod/default.nix
          sed -i "s|rev = \".*\";|rev = \"$rev\";|" "$f"
          sed -i "s|hash = \"sha256-.*\";|hash = \"$hash\";|" "$f"
          sed -i "s|version = \".*\";|version = \"0-unstable-$date\";|" "$f"
        '';
      }))
    ];
  };

  meta = {
    description = "GBZ35 Mod theme for EmulationStation (640x480 handheld)";
    homepage = "https://github.com/Jetup13/es-theme-gbz35_mod";
    license = lib.licenses.cc-by-nc-sa-30;
    platforms = lib.platforms.all;
  };
}
