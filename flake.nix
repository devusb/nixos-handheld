{
  description = "NixOS for handheld gaming devices";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.r36h = nixpkgs.lib.nixosSystem {
        # Builds for aarch64 — use binfmt or remote builder:
        #   --builders 'ssh-ng://nix@superintendent aarch64-linux - - - big-parallel,kvm,nixos-test'
        system = "aarch64-linux";
        modules = [
          ./boards/r36h
        ];
      };

      packages.${system} = {
        r36h-image = self.nixosConfigurations.r36h.config.system.build.sdImage;
        r36h-uInitrd = self.nixosConfigurations.r36h.config.system.build.uInitrd;

        # Standalone kernel build (test cross-compilation without full NixOS eval)
        kernel-rk3326 = let
          pkgsCross = import nixpkgs {
            inherit system;
            crossSystem.system = "aarch64-linux";
          };
        in pkgsCross.callPackage ./pkgs/kernel-rk3326 { };
      };
    };
}
