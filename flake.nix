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
      handheldSystem = "aarch64-linux";
      forAllSystems = nixpkgs.lib.genAttrs (import systems);
      pkgs = self.legacyPackages.${handheldSystem};
      treefmtEval = forAllSystems (
        system: treefmt-nix.lib.evalModule nixpkgs.legacyPackages.${system} ./treefmt.nix
      );
    in
    {
      overlays.default = import ./overlay.nix;

      nixosModules.default = ./modules;

      nixosConfigurations.r36h = nixpkgs.lib.nixosSystem {
        system = handheldSystem;
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
        system = handheldSystem;
        modules = [
          { nixpkgs.config.allowUnfree = true; }
          ./handhelds/rg28xx
        ];
      };

      legacyPackages = forAllSystems (
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [
            self.overlays.default
            nix-packages.overlays.default
          ];
        }
      );

      packages.${handheldSystem} = {
        r36h-image = self.nixosConfigurations.r36h.config.system.build.sdImage;
        rg28xx-image = self.nixosConfigurations.rg28xx.config.system.build.sdImage;
      };

      checks.${handheldSystem} = {
        nixos-r36h = self.nixosConfigurations.r36h.config.system.build.toplevel;
        nixos-rg28xx = self.nixosConfigurations.rg28xx.config.system.build.toplevel;
      };

      formatter = forAllSystems (system: treefmtEval.${system}.config.build.wrapper);
    };
}
