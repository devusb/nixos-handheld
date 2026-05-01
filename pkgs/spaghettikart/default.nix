{
  spaghettikart,
  SDL2_classic,
  requireFile,
  fetchurl,
  zip,
  clangStdenv,
  spdlog,
}:
let
  sse2neon = fetchurl {
    name = "sse2neon.h";
    url = "https://raw.githubusercontent.com/DLTcollab/sse2neon/refs/heads/master/sse2neon.h";
    hash = "sha256-+rXhvglc6NudKrDB/gssbyo0ZXtDzoNojoyEIkgG3zg=";
  };
in
(spaghettikart.override {
  SDL2 = SDL2_classic;
}).overrideAttrs
  (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ zip ];

    cmakeFlags = (old.cmakeFlags or [ ]) ++ [
      "-DUSE_OPENGLES=ON"
    ];


    env.NIX_CFLAGS_COMPILE = "-O3 -fno-lto -Wno-error";

    preConfigure =
      old.preConfigure
      + ''
        mkdir -p sse2neon
        cp ${sse2neon} sse2neon/sse2neon.h
        substituteInPlace CMakeLists.txt \
          --replace-fail 'set(SSE2NEON_DIR ''${CMAKE_BINARY_DIR}/_deps/sse2neon)' "set(SSE2NEON_DIR $(readlink -f ./sse2neon))" \
          --replace-fail 'file(DOWNLOAD "https://raw.githubusercontent.com/DLTcollab/sse2neon/refs/heads/master/sse2neon.h" "''${SSE2NEON_DIR}/sse2neon.h")' ""
      '';

    postBuild =
      old.postBuild
      + ''
        ( cd .. && build/TorchExternal/src/TorchExternal-build/torch o2r ${
          requireFile {
            name = "baserom.us.z64";
            url = "https://github.com/HarbourMasters/SpaghettiKart";
            hash = "sha256-1rhTjdY/ATLssoVufTKBbtPDDj5HmuzSPPg/troXpdo=";
            message = ''
              Mario Kart 64 US ROM not found in the store. Acquire it and run:

                nix-store --add-fixed sha256 baserom.us.z64
            '';
          }
        } )
        # Inject mod metadata at archive root so ModManager recognizes mk64-assets
        ( cd .. && cp meta/mods.toml mods.toml && zip mk64.o2r mods.toml && rm mods.toml )
        cp ../mk64.o2r ./mk64.o2r
      '';

    postInstall =
      old.postInstall
      + ''
        install -Dm644 mk64.o2r $out/share/spaghettikart/mk64.o2r
      '';

    postFixup = ''
      wrapProgram $out/bin/Spaghettify \
        --run 'mkdir -p ~/.local/share/spaghettikart' \
        --run "ln -sf $out/share/spaghettikart/spaghetti.o2r ~/.local/share/spaghettikart/spaghetti.o2r" \
        --run "ln -sf $out/share/spaghettikart/mk64.o2r ~/.local/share/spaghettikart/mk64.o2r" \
        --run "ln -sf $out/share/spaghettikart/gamecontrollerdb.txt ~/.local/share/spaghettikart/gamecontrollerdb.txt" \
        --run "rm -rf ~/.local/share/spaghettikart/meta && ln -sfT $out/share/spaghettikart/meta ~/.local/share/spaghettikart/meta" \
        --run "cp -f $out/share/spaghettikart/config.yml ~/.local/share/spaghettikart/config.yml 2>/dev/null || true" \
        --run "(chmod -R u+w ~/.local/share/spaghettikart/yamls 2>/dev/null || true) && rm -rf ~/.local/share/spaghettikart/yamls && cp -rL --no-preserve=mode $out/share/spaghettikart/yamls ~/.local/share/spaghettikart/yamls" \
        --run 'cd ~/.local/share/spaghettikart'
    '';

    meta = old.meta // {
      platforms = [ "x86_64-linux" "aarch64-linux" ];
    };
  })
