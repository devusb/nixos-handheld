{
  love,
  balatro,
  SDL2_classic,
  requireFile,
}:
let
  love' = love.override {
    SDL2 = SDL2_classic;
  };
in
balatro.override {
  src = requireFile {
    name = "Balatro.exe";
    url = "https://store.steampowered.com/app/2379780/Balatro/";
    hash = "sha256-DXX+FkrM8zEnNNSzesmHiN0V8Ljk+buLf5DE5Z3pP0c=";
    message = ''
      Balatro.exe not found in the store. Acquire it from your Steam install
      at ~/.local/share/Steam/steamapps/common/Balatro/Balatro.exe and run:

        nix-store --add-fixed sha256 Balatro.exe
    '';
  };
  love = love';
  withMods = false;
  withBridgePatch = false;
}
