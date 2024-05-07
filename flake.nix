{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    gitignore.url = "github:hercules-ci/gitignore.nix";
    gitignore.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, ... }:
    inputs.flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import inputs.nixpkgs {inherit system;};
        inherit (inputs.gitignore.lib) gitignoreSource;
      in rec {
        devShells.default = devShells.develop;
        packages.default = packages.vemod;

        devShells.develop = pkgs.mkShell { nativeBuildInputs = with pkgs; [ zig_0_12 zls ]; };
        devShells.use = pkgs.mkShell { nativeBuildInputs = with packages; [ vemod vmdls ]; };

        packages.vemod = pkgs.stdenvNoCC.mkDerivation {
          pname = "vemod";
          version = "master";
          src = gitignoreSource ./.;
          nativeBuildInputs = with pkgs; [ zig ];
          dontConfigure = true;
          dontInstall = true;
          doCheck = true;
          buildPhase = ''
            export XDG_CACHE_HOME=$(mktemp -d)
            zig build vemod --prefix $out -Doptimize=ReleaseFast
            rm -rf $XDG_CACHE_HOME
          '';
          checkPhase = ''
            export XDG_CACHE_HOME=$(mktemp -d)
            zig fmt --check .
            zig build test
            rm -rf $XDG_CACHE_HOME
          '';
        };

        packages.vmdls = pkgs.stdenvNoCC.mkDerivation {
          pname = "vmdls";
          version = "master";
          src = gitignoreSource ./.;
          nativeBuildInputs = with pkgs; [ zig ];
          dontConfigure = true;
          dontInstall = true;
          doCheck = true;
          buildPhase = ''
            export XDG_CACHE_HOME=$(mktemp -d)
            zig build vmdls --prefix $out -Doptimize=ReleaseFast
            rm -rf $XDG_CACHE_HOME
          '';
          checkPhase = ''
            export XDG_CACHE_HOME=$(mktemp -d)
            zig fmt --check .
            zig build test
            rm -rf $XDG_CACHE_HOME
          '';
        };
      }
    );
}
