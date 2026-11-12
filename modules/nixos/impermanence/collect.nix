# Collects the `persist`/`cache` quirks (modules/den/quirks/impermanence.nix)
# across a host's full aspect-includes chain and wires the merged result into
# environment.persistence. `persist`/`cache` are special module args den
# auto-injects — each is the list of every included aspect's own top-level
# `persist`/`cache` attrset (e.g. modules/nixos/services/k3s/k3s.nix's
# `persist.directories = [...]`).
{
  den.aspects.impermanence.collect = {
    nixos =
      {
        persist,
        cache,
        lib,
        ...
      }:
      let
        merge = entries: {
          directories = entries |> lib.concatMap (e: e.directories or [ ]) |> lib.unique;
          files = entries |> lib.concatMap (e: e.files or [ ]) |> lib.unique;
        };
      in
      {
        environment.persistence."/persist" = merge persist;
        environment.persistence."/cache" = merge cache;
      };
  };
}
