{
  retroarch-joypad-autoconfig,
}:
retroarch-joypad-autoconfig.overrideAttrs (old: {
  postInstall = (old.postInstall or "") + ''
    cp ${./autoconfig/udev/r36s_Gamepad.cfg} $out/share/libretro/autoconfig/udev/
    cp ${./autoconfig/udev/gpio-keys.cfg} $out/share/libretro/autoconfig/udev/
    cp ${./autoconfig/udev/adc-joystick.cfg} $out/share/libretro/autoconfig/udev/
  '';
})
