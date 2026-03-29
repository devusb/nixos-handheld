{
  description = "NixOS for handheld gaming devices";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "aarch64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ self.overlays.default ];
      };
    in
    {
      overlays.default = import ./overlay.nix;

      nixosModules.default = ./modules;

      nixosConfigurations.r36h = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          { nixpkgs.config.allowUnfree = true; }
          ./boards/r36h
        ];
      };

      packages.${system} = {
        r36h-image = self.nixosConfigurations.r36h.config.system.build.sdImage;
        linux-rk3326 = pkgs.linux-rk3326;
        retroarch-handheld = pkgs.retroarch-handheld;
      };
    };
}
