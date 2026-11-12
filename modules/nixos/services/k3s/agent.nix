# k3s agent (worker) aspect. Joins the server named by its
# `settings.k3s.agent.serverHost`, with the cluster token from k3s.token.
{
  config,
  den,
  lib,
  ...
}:
let
  inherit (config.den) devices;
in
{
  den.aspects.k3s.agent = {
    settings.serverHost = lib.mkOption {
      type = lib.types.str;
      description = "den.hosts name of the k3s server this agent joins";
    };

    includes = [
      den.aspects.k3s.containerd
      den.aspects.k3s.node-base
      den.aspects.k3s.token
    ];

    k3s-nodes =
      { host, ... }:
      {
        hostname = host.name;
        inherit (devices.${host.name}) address;
        role = "agent";
        cluster = host.settings.k3s.clusterName;
      };

    nixos =
      { host, ... }:
      {
        services.k3s = {
          enable = true;
          role = "agent";
          serverAddr = "https://${devices.${host.settings.k3s.agent.serverHost}.address}:6443";
          extraFlags = [
            # Bare path, not unix://…, see k3s.nix.
            "--container-runtime-endpoint=/run/containerd/containerd.sock"
            "--node-ip=${devices.${host.name}.address}"
          ];
        };
      };
  };
}
