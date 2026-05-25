{
  nixpkgs.overlays = [ (import ../overlay.nix) ];

  imports = [
    ./options.nix
    ./retroarch
    ./emulationstation
    ./gpu
    ./portmaster
    ./fake-suspend
    ./hardware.nix
    ./diagnostics.nix
  ];
}
