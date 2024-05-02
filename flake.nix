{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    zig-overlay.url = "github:mitchellh/zig-overlay";
    zig-overlay.inputs.nixpkgs.follows = "nixpkgs";

    zls.url = "github:zigtools/zls";
    zls.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    zig-overlay,
    zls,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {inherit system;};
        zigpkg = zig-overlay.packages.${system}."0.12.0";
        zlspkg = zls.packages.${system}.zls;
      in {
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
              zigpkg
              zlspkg
          ];
        };

        devShell = self.devShells.${system}.default;
      }
    );
}
