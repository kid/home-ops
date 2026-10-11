# k3s agent (worker) aspect. Joins the server named by the freeform
# host.k3s.serverHost field, with the server's node-token from
# secrets/clusters/<cluster>/k3s-token.sops.
{
  config,
  den,
  inputs,
  ...
}:
let
  inherit (config.den) devices;
in
{
  den.aspects.k3s-agent = {
    includes = [
      den.aspects.k3s-containerd
      den.aspects.k3s-node-base
    ];

    k3s-nodes =
      { host, ... }:
      {
        hostname = host.name;
        inherit (devices.${host.name}) address;
        role = "agent";
      };

    nixos =
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

        services.k3s = {
          enable = true;
          role = "agent";
          serverAddr = "https://${devices.${host.k3s.serverHost}.address}:6443";
          tokenFile = config.sops.secrets.k3s-token.path;
          extraFlags = [
            # Bare path, not unix://…, see k3s.nix.
            "--container-runtime-endpoint=/run/containerd/containerd.sock"
            "--node-ip=${devices.${host.name}.address}"
          ];
        };

        # Only exists with sops.useSystemdActivation; a no-op otherwise.
        systemd.services.k3s = {
          after = [ "sops-install-secrets.service" ];
          wants = [ "sops-install-secrets.service" ];
        };
      };
  };
}
