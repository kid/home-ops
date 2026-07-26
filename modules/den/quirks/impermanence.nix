# Quirk metadata registration, ported verbatim from nixopslab's
# modules/den/quirks/impermanence.nix. Actual collection happens in
# modules/den/aspects/impermanence/persist-collector.nix, which reads the
# `persist`/`cache` args den auto-injects by walking a host's aspect-includes
# chain for these quirk names.
{
  den.quirks.persist.description = "Persistent directories/files collected from aspects (host)";
  den.quirks.cache.description = "Cache directories/files collected from aspects (host)";
  den.quirks.persistHome.description = "Persistent directories/files collected from aspects (user)";
  den.quirks.cacheHome.description = "Cache directories/files collected from aspects (user)";
}
