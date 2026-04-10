{ lib, ... }:

{
  options.handheld.romsDirectory = lib.mkOption {
    type = lib.types.str;
    default = "/roms";
    description = ''
      Root directory where ROM files are organized into per-system subdirectories.
      RetroArch derives `bios`, `saves`, and `states` subdirectories from this path.
      EmulationStation's default systems use `''${romsDirectory}/<system>` as their ROM path.
      The module does not create this directory — the consumer is responsible for ensuring
      it exists (typically as a mount point or a pre-populated directory).
    '';
  };
}
