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

        devShells = rec {
          default = develop;
          develop = pkgs.mkShell { nativeBuildInputs = with pkgs; [ zig_0_12 zls ]; };
          use = pkgs.mkShell { nativeBuildInputs = with packages; [ vemod vmdls ]; };
        };

        packages = 
          let
            commonDrvAttrs = {
              src = gitignoreSource ./.;
              nativeBuildInputs = with pkgs; [ zig ];
              dontConfigure = true;
              dontInstall = true;
              doCheck = true;
              checkPhase = ''
                export XDG_CACHE_HOME=$(mktemp -d)
                zig fmt --check .
                zig build test
                rm -rf $XDG_CACHE_HOME
              '';
            };
          in
          rec {
            default = vemod;

            vemod = pkgs.stdenvNoCC.mkDerivation (commonDrvAttrs // {
              pname = "vemod";
              version = "master";
              buildPhase = ''
                export XDG_CACHE_HOME=$(mktemp -d)
                zig build vemod --prefix $out -Doptimize=ReleaseFast
                rm -rf $XDG_CACHE_HOME
              '';
            });

            vmdls = pkgs.stdenvNoCC.mkDerivation (commonDrvAttrs // {
              pname = "vmdls";
              version = "master";
              buildPhase = ''
                export XDG_CACHE_HOME=$(mktemp -d)
                zig build vmdls --prefix $out -Doptimize=ReleaseFast
                rm -rf $XDG_CACHE_HOME
              '';
            });
          };
      }
    );
}
