{
  description = "Spotifast (crmne/spotifast) packaged for Nix/NixOS";

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
        spotifast = self.packages.${system}.default;
      };

      overlays.default = final: prev: {
        spotifast = final.callPackage ./package.nix {};
      };
    };
}
