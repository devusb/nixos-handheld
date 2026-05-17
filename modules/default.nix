{
  nixpkgs.overlays = [ (import ../overlay.nix) ];

  imports = [
    ./options.nix
    ./retroarch
    ./emulationstation
    ./gpu
    ./portmaster
    ./hardware.nix
    ./diagnostics.nix
  ];
}
