{
  nixpkgs.overlays = [ (import ../overlay.nix) ];

  imports = [
    ./retroarch
    ./hardware.nix
    ./diagnostics.nix
  ];
}
