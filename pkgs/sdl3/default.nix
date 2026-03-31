{
  sdl3,
  ...
}:
(sdl3.override {
  libdecorSupport = false;
  pipewireSupport = false;
  pulseaudioSupport = false;
  waylandSupport = false;
  x11Support = false;
}).overrideAttrs
  (old: {
    cmakeFlags = old.cmakeFlags ++ [ "-DSDL_UNIX_CONSOLE_BUILD=ON" ];
    doCheck = false;
  })
