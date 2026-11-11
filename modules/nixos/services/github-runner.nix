# The home-ops GitHub Actions runner (modules/hosts/gha.nix): one ephemeral
# runner labelled `nix`, registered on every start through the
# `homeopsrunner` GitHub App (repository permission Administration:
# read and write, installed on kid/home-ops only), whose private key is in
# secrets/hosts/gha/github-app-key.sops.
# Builds go to the nix builders (modules/nixos/services/nix-builders.nix).
{ inputs, ... }:
{
  den.aspects.github-runner.nixos =
    { config, ... }:
    {
      imports = [ inputs.sops-nix.nixosModules.sops ];

      sops.secrets.github-app-key = {
        sopsFile = ../../../secrets/hosts/gha/github-app-key.sops;
        format = "binary";
      };

      services.github-runners.home-ops = {
        enable = true;
        name = "gha";
        url = "https://github.com/kid/home-ops";
        githubApp = {
          # The NixOS module takes the numeric App ID only (an int); GitHub
          # still accepts it as the JWT issuer next to the client ID.
          id = 5718196;
          login = "kid";
          privateKeyFile = config.sops.secrets.github-app-key.path;
        };
        ephemeral = true;
        replace = true;
        extraLabels = [ "nix" ];
      };
      # Only exists with sops.useSystemdActivation; a no-op otherwise.
      systemd.services.github-runner-home-ops = {
        after = [ "sops-install-secrets.service" ];
        wants = [ "sops-install-secrets.service" ];
      };

      nix.settings = {
        # The runner evaluates this flake.
        extra-experimental-features = [ "pipe-operators" ];
        # The runner's user isn't trusted, so flake.nixConfig's cache
        # (modules/flake/charts.nix) is ignored.
        extra-substituters = [ "https://nixhelm.cachix.org" ];
        extra-trusted-public-keys = [
          "nixhelm.cachix.org-1:esqauAsR4opRF0UsGrA6H3gD21OrzMnBBYvJXeddjtY="
        ];
        # Remote build outputs are copied back here.
        min-free = 15 * 1024 * 1024 * 1024;
        max-free = 30 * 1024 * 1024 * 1024;
      };
    };
}
