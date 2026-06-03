{
  description = "NixOS for handheld gaming devices";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    systems.url = "github:nix-systems/default";
    nix-packages.url = "github:devusb/nix-packages";
    nix-packages.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      treefmt-nix,
      systems,
      nix-packages,
    }:
    let
      system = "aarch64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [
          self.overlays.default
          nix-packages.overlays.default
        ];
      };
      eachSystem = f: nixpkgs.lib.genAttrs (import systems) (system: f nixpkgs.legacyPackages.${system});
      treefmtEval = eachSystem (pkgs: treefmt-nix.lib.evalModule pkgs ./treefmt.nix);
    in
    {
      overlays.default = import ./overlay.nix;

      nixosModules.default = ./modules;

      nixosConfigurations.r36h = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./handhelds/r36h
          {
            nixpkgs.config.allowUnfree = true;
            systemd.services.emulationstation.path = [
              pkgs.balatro
              pkgs.openjkdf2-gles
            ];
          }
        ];
      };

      nixosConfigurations.rg28xx = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          { nixpkgs.config.allowUnfree = true; }
          ./handhelds/rg28xx
        ];
      };

      legacyPackages.${system} = pkgs;

      packages.${system} = {
        r36h-image = self.nixosConfigurations.r36h.config.system.build.sdImage;
        rg28xx-image = self.nixosConfigurations.rg28xx.config.system.build.sdImage;
      };

      checks.${system} = {
        nixos-r36h = self.nixosConfigurations.r36h.config.system.build.toplevel;
        nixos-rg28xx = self.nixosConfigurations.rg28xx.config.system.build.toplevel;
      };

      formatter = eachSystem (pkgs: treefmtEval.${pkgs.system}.config.build.wrapper);
    };
}
