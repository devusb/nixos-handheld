{
  nixpkgs.overlays = [ (import ../overlay.nix) ];

  imports = [
    ./options.nix
    ./retroarch
    ./emulationstation
    ./hardware.nix
    ./diagnostics.nix
  ];
}
