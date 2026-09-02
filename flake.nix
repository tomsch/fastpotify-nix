{
  description = "Fastpotify (crmne/fastpotify) packaged for Nix/NixOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
      };
    in {
      packages.${system} = {
        default = pkgs.callPackage ./package.nix {};
        fastpotify = self.packages.${system}.default;
        nix-prefetch-git = pkgs.nix-prefetch-git;
      };

      overlays.default = final: prev: {
        fastpotify = final.callPackage ./package.nix {};
      };
    };
}
