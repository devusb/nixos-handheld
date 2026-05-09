{
  nixpkgs.overlays = [ (import ../overlay.nix) ];

  imports = [
    ./options.nix
    ./retroarch
    ./emulationstation
    ./gpu
    ./hardware.nix
    ./diagnostics.nix
  ];
}
