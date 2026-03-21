{
  description = "NixOS for handheld gaming devices";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    {
      # Placeholder — will be populated in later tasks
      packages.x86_64-linux = { };
    };
}
