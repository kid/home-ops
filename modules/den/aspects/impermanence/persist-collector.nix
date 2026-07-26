# Collects the `persist`/`cache` quirks (modules/den/quirks/impermanence.nix)
# across a host's full aspect-includes chain and wires the merged result into
# environment.persistence. Ported verbatim from nixopslab's
# modules/den/aspects/impermanence/persist-collector.nix. `persist`/`cache`
# are special module args den auto-injects — each is the list of every
# included aspect's own top-level `persist`/`cache` attrset (e.g.
# modules/den/aspects/services/k3s.nix's `persist.directories = [...]`).
{
  den.aspects.impermanence.persist-collector = {
    nixos =
      {
        persist,
        cache,
        lib,
        ...
      }:
      let
        mergePersist = entries: {
          directories = lib.unique (lib.concatMap (e: e.directories or [ ]) entries);
          files = lib.unique (lib.concatMap (e: e.files or [ ]) entries);
        };
      in
      {
        environment.persistence."/persist" = mergePersist persist;
        environment.persistence."/cache" = mergePersist cache;
      };
  };
}
