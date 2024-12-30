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
        use_zig_overlay = false;
        zig = pkgs.zig_0_13;
        inherit (inputs.gitignore.lib) gitignoreSource;
      in rec {

        devShells = rec {
          default = develop;
          develop = pkgs.mkShell { nativeBuildInputs = [ zig ] ++ (with pkgs; [ zls clang-tools qbe ]); };
          use = pkgs.mkShell { nativeBuildInputs = with packages; [ vemod-no-check vmdls-no-check ]; };
          use-debug = pkgs.mkShell { nativeBuildInputs = with packages; [ vemod-debug vmdls-debug ]; };
        };

        packages = 
          let
            mkVemodPkg = { pname, version ? "master", doCheck ? true, optimize ? "ReleaseFast" }: 
              pkgs.stdenvNoCC.mkDerivation {
                inherit pname version doCheck;
                src = gitignoreSource ./.;
                nativeBuildInputs = [ zig ];
                dontConfigure = true;
                dontInstall = true;
                buildPhase = ''
                  export XDG_CACHE_HOME=$(mktemp -d)
                  zig build ${pname} --prefix $out -Doptimize=${optimize}
                  rm -rf $XDG_CACHE_HOME
                '';
                checkPhase = ''
                  export XDG_CACHE_HOME=$(mktemp -d)
                  zig fmt --check .
                  zig build test
                  zig build end-to-end-test
                  rm -rf $XDG_CACHE_HOME
                '';
              };
          in
          rec {
            default = vemod;
            vemod = mkVemodPkg { pname = "vemod"; };
            vmdls = mkVemodPkg { pname = "vmdls"; };
            vemod-debug = mkVemodPkg { pname = "vemod"; doCheck = false; optimize = "Debug"; };
            vmdls-debug = mkVemodPkg { pname = "vmdls"; doCheck = false; optimize = "Debug"; };
            vemod-no-check = mkVemodPkg { pname = "vemod"; doCheck = false; };
            vmdls-no-check = mkVemodPkg { pname = "vmdls"; doCheck = false; };
          };
      }
    );
}
