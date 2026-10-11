{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  nix-update-script,
}:

stdenvNoCC.mkDerivation {
  pname = "es-theme-gbz35-mod";
  version = "0-unstable-2021-09-19";

  src = fetchFromGitHub {
    owner = "Jetup13";
    repo = "es-theme-gbz35_mod";
    rev = "4605d6805c2a24cadffe5a331868da4f8ddbe1df";
    hash = "sha256-c9Ycnb5Etc7GaNyPhq1qiSH0l4IA6vh1/Cn17eTlWI4=";
  };

  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    cp -r . $out
    runHook postInstall
  '';

  passthru = {
    themeName = "gbz35_mod";
    updateScript = nix-update-script {
      extraArgs = [
        "--flake"
        "--version=branch"
      ];
    };
  };

  meta = {
    description = "GBZ35 Mod theme for EmulationStation (640x480 handheld)";
    homepage = "https://github.com/Jetup13/es-theme-gbz35_mod";
    license = lib.licenses.cc-by-nc-sa-30;
    platforms = lib.platforms.all;
  };
}
