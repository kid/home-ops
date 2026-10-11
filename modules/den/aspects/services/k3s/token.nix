# The cluster's join token, from secrets/clusters/<cluster>/k3s-token.sops
# (`nix run .#provision-k3s-token <cluster>`). A server that has it at its
# first start adopts it instead of generating one; an existing server only
# accepts the token its datastore was bootstrapped with.
{ inputs, ... }:
{
  den.aspects.k3s-token.nixos =
    { host, config, ... }:
    let
      clusterName = host.k3s.clusterName or "prd";
    in
    {
      imports = [ inputs.sops-nix.nixosModules.sops ];

      sops.secrets.k3s-token = {
        sopsFile = ../../../../../secrets/clusters/${clusterName}/k3s-token.sops;
        format = "binary";
      };

      services.k3s.tokenFile = config.sops.secrets.k3s-token.path;

      # Only exists with sops.useSystemdActivation; a no-op otherwise.
      systemd.services.k3s = {
        after = [ "sops-install-secrets.service" ];
        wants = [ "sops-install-secrets.service" ];
      };
    };
}
