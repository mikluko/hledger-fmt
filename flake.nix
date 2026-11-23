{
  description = "hledger add-on: format-preserving journal formatter";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      # Adds hledger-fmt to the consumer's haskellPackages.
      overlays.default = final: prev: {
        haskellPackages = prev.haskellPackages.extend (
          hfinal: _: {
            hledger-fmt = hfinal.callCabal2nix "hledger-fmt" self { };
          }
        );
        hledger-fmt = final.haskell.lib.justStaticExecutables final.haskellPackages.hledger-fmt;
      };

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.haskellPackages.ghc
              pkgs.cabal-install
              pkgs.hlint
              pkgs.haskellPackages.fourmolu
            ];
          };
        }
      );
    };
}
