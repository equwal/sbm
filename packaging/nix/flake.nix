{
  description = "sbm: bookmarks in a plain file, picked with dmenu or fzf";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        sbm = pkgs.callPackage ./default.nix { };
        default = sbm;
      });

      # Build the working tree instead of the tagged release:
      #   nix build .#sbm --override-input nixpkgs ...
      # or edit src in default.nix to fetchGit ../..
      # What "make check" wants, plus the runtime programs. dmenu is left out
      # on purpose: it is X11 only and does not evaluate on Darwin.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = with pkgs; [ shellcheck fzf curl jq git ];
        };
      });
    };
}
