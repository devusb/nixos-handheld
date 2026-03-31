{
  description = "NixOS for handheld gaming devices";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    systems.url = "github:nix-systems/default";
  };

  outputs = { self, nixpkgs, treefmt-nix, systems }:
    let
      system = "aarch64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
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
          { nixpkgs.config.allowUnfree = true; }
          ./boards/r36h
        ];
      };

      packages.${system} = {
        r36h-image = self.nixosConfigurations.r36h.config.system.build.sdImage;
        linux-rk3326 = pkgs.callPackage ./pkgs/kernel-rk3326 { };
      };

      formatter = eachSystem (pkgs: treefmtEval.${pkgs.system}.config.build.wrapper);
    };
}
