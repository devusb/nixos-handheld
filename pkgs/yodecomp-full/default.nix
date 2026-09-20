{
  yodecomp,
  requireFile,
  sdl3,
}:

yodecomp.override {
  # This repo's sdl3 is the KMSDRM console build, which cannot reach cage.
  inherit sdl3;

  retailData = requireFile {
    name = "Yoda.zip";
    hash = "sha256-dsRoojL01tcs0fkrmd2Jo2AAXVAwRVbgVA6eH0Dnd6w=";
    message = ''
      Yoda.zip not found in the store. Archive a retail Yoda Stories install
      with the game in a top-level Yoda/ directory, then run:

        nix-store --add-fixed sha256 Yoda.zip
    '';
  };
}
