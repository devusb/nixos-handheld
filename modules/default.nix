{
  nixpkgs.overlays = [ (import ../overlay.nix) ];

  imports = [
    ./retroarch
    ./emulationstation
    ./hardware.nix
    ./diagnostics.nix
  ];
}
