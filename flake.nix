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
            vemod-package = { pname, version ? "master" }: pkgs.stdenvNoCC.mkDerivation {
              inherit pname version;
              src = gitignoreSource ./.;
              nativeBuildInputs = with pkgs; [ zig ];
              dontConfigure = true;
              dontInstall = true;
              doCheck = true;
              buildPhase = ''
                export XDG_CACHE_HOME=$(mktemp -d)
                zig build ${pname} --prefix $out -Doptimize=ReleaseFast
                rm -rf $XDG_CACHE_HOME
              '';
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
            vemod = vemod-package { pname = "vemod"; };
            vmdls = vemod-package { pname = "vmdls"; };
          };
      }
    );
}
