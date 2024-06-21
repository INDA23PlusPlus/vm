# Provides necessary environment for running dgbjit and benchjit
# Activate with nix-shell ./jit-shell.nix
{
  pkgs ? import <nixpkgs> {}
}:

pkgs.mkShell {
  packages = with pkgs; [ hyperfine
                          luajit
                          pypy
                          gdb
                        ];
}
