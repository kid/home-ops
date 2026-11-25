# Work host, user, and AI setup live in kid/nixfiles-work; `just` swaps that repo
# in with --override-input, else ./private is an empty stub. Its modules must not
# declare flake-file.inputs: write-flake would put them in home-ops' public flake.nix.
{ inputs, lib, ... }:
{
  flake-file.inputs.private = {
    url = "path:./private";
    flake = false;
  };

  imports = lib.optional (inputs ? private) (inputs.import-tree "${inputs.private}/modules");
}
