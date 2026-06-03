{
  nixpkgs.overlays = [ (import ../overlay.nix) ];

  imports = [
    ./options.nix
    ./users.nix
    ./retroarch
    ./emulationstation
    ./gpu
    ./portmaster
    ./compositor
    ./hardware.nix
    ./diagnostics.nix
  ];
}
