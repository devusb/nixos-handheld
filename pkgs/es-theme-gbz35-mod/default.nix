{
  lib,
  fetchFromGitHub,
}:

fetchFromGitHub {
  owner = "Jetup13";
  repo = "es-theme-gbz35_mod";
  rev = "4605d6805c2a24cadffe5a331868da4f8ddbe1df";
  hash = "sha256-c9Ycnb5Etc7GaNyPhq1qiSH0l4IA6vh1/Cn17eTlWI4=";

  passthru.themeName = "gbz35_mod";

  meta = {
    description = "GBZ35 Mod theme for EmulationStation (640x480 handheld)";
    homepage = "https://github.com/Jetup13/es-theme-gbz35_mod";
    license = lib.licenses.cc-by-nc-sa-30;
    platforms = lib.platforms.all;
  };
}
