{
  description = "NixOS for handheld gaming devices";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-packages.url = "github:devusb/nix-packages/battleship";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    systems.url = "github:nix-systems/default";
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-packages,
      treefmt-nix,
      systems,
    }:
    let
      system = "aarch64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ nix-packages.overlays.default self.overlays.default ];
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
            systemd.services.emulationstation.path = [ pkgs.balatro pkgs.battleship ];
          }
        ];
      };

      legacyPackages.${system} = pkgs;

      packages.${system} = {
        r36h-image = self.nixosConfigurations.r36h.config.system.build.sdImage;
      };

      checks.${system} = {
        nixos-r36h = self.nixosConfigurations.r36h.config.system.build.toplevel;
      };

      formatter = eachSystem (pkgs: treefmtEval.${pkgs.system}.config.build.wrapper);
    };
}
