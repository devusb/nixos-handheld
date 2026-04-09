# System → RetroArch core mapping for es_systems.cfg
{ pkgs, retroarchPkg }:

let

  # The retroarch-handheld wrapper is a symlinkJoin with all cores merged.
  # Cores live at $out/lib/retroarch/cores/<name>_libretro.so.
  # The wrapper already has --appendconfig baked in, so we just need -L <core>.
  mkCommand =
    core:
    "${retroarchPkg}/bin/retroarch -L ${retroarchPkg}/lib/retroarch/cores/${core}_libretro.so %ROM%";

  systems = {
    gb = {
      fullname = "Game Boy";
      extensions = ".gb .GB .zip .ZIP .7z";
      core = "gambatte";
      platform = "gb";
    };
    gbc = {
      fullname = "Game Boy Color";
      extensions = ".gbc .GBC .zip .ZIP .7z";
      core = "gambatte";
      platform = "gbc";
    };
    gba = {
      fullname = "Game Boy Advance";
      extensions = ".gba .GBA .zip .ZIP .7z";
      core = "mgba";
      platform = "gba";
    };
    nes = {
      fullname = "Nintendo Entertainment System";
      extensions = ".nes .NES .zip .ZIP .7z";
      core = "fceumm";
      platform = "nes";
    };
    snes = {
      fullname = "Super Nintendo";
      extensions = ".smc .sfc .SMC .SFC .zip .ZIP .7z";
      core = "snes9x";
      platform = "snes";
    };
    megadrive = {
      fullname = "Sega Mega Drive / Genesis";
      extensions = ".md .gen .bin .MD .GEN .BIN .zip .ZIP .7z";
      core = "genesis_plus_gx";
      platform = "megadrive";
    };
    sega32x = {
      fullname = "Sega 32X";
      extensions = ".32x .32X .zip .ZIP .7z";
      core = "picodrive";
      platform = "sega32x";
    };
    ngp = {
      fullname = "Neo Geo Pocket";
      extensions = ".ngp .ngc .NGP .NGC .zip .ZIP .7z";
      core = "mednafen_ngp";
      platform = "ngp";
    };
    psx = {
      fullname = "PlayStation";
      extensions = ".bin .cue .pbp .chd .m3u .BIN .CUE .PBP .CHD .M3U .zip .ZIP .7z";
      core = "pcsx_rearmed";
      platform = "psx";
    };
    n64 = {
      fullname = "Nintendo 64";
      extensions = ".n64 .z64 .v64 .N64 .Z64 .V64 .zip .ZIP .7z";
      core = "mupen64plus_next";
      platform = "n64";
    };
    nds = {
      fullname = "Nintendo DS";
      extensions = ".nds .NDS .zip .ZIP .7z";
      command = "for fd in /proc/self/fd/*; do case $(readlink $fd) in /dev/dri/*) eval \"exec $(basename $fd)>&-\";; esac; done; exec ${pkgs.drastic}/bin/drastic %ROM%";
      platform = "nds";
    };
    psp = {
      fullname = "PlayStation Portable";
      extensions = ".iso .cso .pbp .ISO .CSO .PBP";
      core = "ppsspp";
      platform = "psp";
    };
    arcade = {
      fullname = "Arcade";
      extensions = ".zip .ZIP .7z";
      core = "fbneo";
      platform = "arcade";
    };
    neogeo = {
      fullname = "Neo Geo";
      extensions = ".zip .ZIP .7z";
      core = "fbneo";
      platform = "neogeo";
    };
    dos = {
      fullname = "DOS";
      extensions = ".zip .dosz .ZIP .DOSZ";
      core = "dosbox_pure";
      platform = "pc";
    };
    threedo = {
      fullname = "3DO";
      extensions = ".iso .bin .chd .ISO .BIN .CHD";
      core = "opera";
      platform = "3do";
      theme = "3do";
    };
    mame = {
      fullname = "MAME";
      extensions = ".zip .ZIP .7z";
      core = "mame2003_plus";
      platform = "mame";
    };
    scummvm = {
      fullname = "ScummVM";
      extensions = ".scummvm";
      core = "scummvm";
      platform = "scummvm";
    };
  };

  systemToXml = name: sys: ''
    <system>
      <name>${name}</name>
      <fullname>${sys.fullname}</fullname>
      <path>/roms/${name}</path>
      <extension>${sys.extensions}</extension>
      <command>${sys.command or (mkCommand sys.core)}</command>
      <platform>${sys.platform}</platform>
      <theme>${sys.theme or name}</theme>
    </system>'';

  systemsXml = builtins.concatStringsSep "\n" (
    builtins.attrValues (builtins.mapAttrs systemToXml systems)
  );
in
pkgs.writeText "es_systems.cfg" ''
  <?xml version="1.0"?>
  <systemList>
  ${systemsXml}
  </systemList>
''
