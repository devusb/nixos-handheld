{
  retroarch-joypad-autoconfig,
}:
retroarch-joypad-autoconfig.overrideAttrs (old: {
  postInstall = (old.postInstall or "") + ''
    cp ${./autoconfig/udev/r36s_Gamepad.cfg} $out/share/libretro/autoconfig/udev/
    # RA looks up autoconfigs by the `input_device` value inside the file,
    # not the filename — so the on-disk underscore name is fine even
    # though the device reports itself as "H700 Gamepad" with a space.
    cp ${./autoconfig/udev/H700_Gamepad.cfg} "$out/share/libretro/autoconfig/udev/H700 Gamepad.cfg"
  '';
})
