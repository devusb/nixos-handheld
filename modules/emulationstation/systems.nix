# Default EmulationStation systems. Each entry matches the submodule type in
# modules/emulationstation/default.nix; the `path` default (derived from
# handheld.romsDirectory) is applied there. The `nds` entry is only present
# when drastic is enabled.
{
  lib,
  pkgs,
  drasticEnabled,
  drasticPackage,
  drasticStateDirectory,
}:

let
  libretro = pkgs.libretro;

  # Close DRM fds inherited from ES so the child can open its own KMSDRM context.
  mkKmsDrmCommand = cmd: ''
    for fd in /proc/self/fd/*; do
      case $(readlink $fd) in /dev/dri/*) eval "exec $(basename $fd)>&-";; esac
    done
    ${cmd}
  '';

  base = {
    gb = {
      fullname = "Game Boy";
      extensions = ".gb .GB .zip .ZIP .7z";
      retroarchCore = libretro.gambatte;
    };
    gbc = {
      fullname = "Game Boy Color";
      extensions = ".gbc .GBC .zip .ZIP .7z";
      retroarchCore = libretro.gambatte;
    };
    gba = {
      fullname = "Game Boy Advance";
      extensions = ".gba .GBA .zip .ZIP .7z";
      retroarchCore = libretro.gpsp;
    };
    nes = {
      fullname = "Nintendo Entertainment System";
      extensions = ".nes .NES .zip .ZIP .7z";
      retroarchCore = libretro.fceumm;
    };
    snes = {
      fullname = "Super Nintendo";
      extensions = ".smc .sfc .SMC .SFC .zip .ZIP .7z";
      retroarchCore = libretro.snes9x;
    };
    megadrive = {
      fullname = "Sega Mega Drive / Genesis";
      extensions = ".md .gen .bin .MD .GEN .BIN .zip .ZIP .7z";
      retroarchCore = libretro.genesis-plus-gx;
    };
    segacd = {
      fullname = "Sega CD";
      extensions = ".cue .zip .ZIP .7z .CUE .m3u .M3U .chd .CHD";
      retroarchCore = libretro.picodrive;
    };
    sega32x = {
      fullname = "Sega 32X";
      extensions = ".32x .32X .zip .ZIP .7z";
      retroarchCore = libretro.picodrive;
    };
    ngp = {
      fullname = "Neo Geo Pocket";
      extensions = ".ngp .ngc .NGP .NGC .zip .ZIP .7z";
      retroarchCore = libretro.beetle-ngp;
    };
    psx = {
      fullname = "PlayStation";
      extensions = ".bin .cue .pbp .chd .m3u .BIN .CUE .PBP .CHD .M3U .zip .ZIP .7z";
      retroarchCore = libretro.pcsx-rearmed;
    };
    n64 = {
      fullname = "Nintendo 64";
      extensions = ".n64 .z64 .v64 .N64 .Z64 .V64 .zip .ZIP .7z";
      retroarchCore = libretro.mupen64plus;
    };
    dreamcast = {
      fullname = "Sega Dreamcast";
      extensions = ".chd .cdi .gdi .CHD .CDI .GDI .zip .ZIP .7z";
      retroarchCore = libretro.flycast;
    };
    psp = {
      fullname = "PlayStation Portable";
      extensions = ".iso .cso .pbp .ISO .CSO .PBP";
      retroarchCore = libretro.ppsspp;
    };
    arcade = {
      fullname = "Arcade";
      extensions = ".zip .ZIP .7z";
      retroarchCore = libretro.fbneo;
    };
    neogeo = {
      fullname = "Neo Geo";
      extensions = ".zip .ZIP .7z";
      retroarchCore = libretro.fbneo;
    };
    dos = {
      fullname = "DOS";
      extensions = ".zip .dosz .ZIP .DOSZ";
      platform = "pc";
      retroarchCore = libretro.dosbox-pure;
    };
    threedo = {
      fullname = "3DO";
      extensions = ".iso .bin .chd .ISO .BIN .CHD";
      platform = "3do";
      theme = "3do";
      retroarchCore = libretro.opera;
    };
    mame = {
      fullname = "MAME";
      extensions = ".zip .ZIP .7z";
      retroarchCore = libretro.mame2003-plus;
    };
    scummvm = {
      fullname = "ScummVM";
      extensions = ".scummvm";
      retroarchCore = libretro.scummvm;
    };
    ports = {
      fullname = "Ports";
      extensions = ".sh .SH";
      platform = "pc";
      theme = "ports";
      command = mkKmsDrmCommand "exec ${pkgs.lib.getExe pkgs.bash} %ROM%";
    };
  };

  ndsEntry = {
    nds = {
      fullname = "Nintendo DS";
      extensions = ".nds .NDS .zip .ZIP .7z";
      # DraStic reads all state from cwd (no CLI flag to override), so we cd before exec.
      command = mkKmsDrmCommand "cd ${drasticStateDirectory} && exec ${drasticPackage}/bin/drastic %ROM%";
    };
  };
in
base // (lib.optionalAttrs drasticEnabled ndsEntry)
