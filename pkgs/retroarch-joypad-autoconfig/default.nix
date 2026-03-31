{
  retroarch-joypad-autoconfig,
}:
retroarch-joypad-autoconfig.overrideAttrs (old: {
  postInstall = (old.postInstall or "") + ''
    cp ${./autoconfig/udev/r36s_Gamepad.cfg} $out/share/libretro/autoconfig/udev/
  '';
})
