# k3s agent (worker) aspect. Joins the server named by the freeform
# host.k3s.serverHost field, with the cluster token from k3s-token.
{
  config,
  den,
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
      den.aspects.k3s-token
    ];

    k3s-nodes =
      { host, ... }:
      {
        hostname = host.name;
        inherit (devices.${host.name}) address;
        role = "agent";
      };

    nixos =
      { host, ... }:
      {
        services.k3s = {
          enable = true;
          role = "agent";
          serverAddr = "https://${devices.${host.k3s.serverHost}.address}:6443";
          extraFlags = [
            # Bare path, not unix://…, see k3s.nix.
            "--container-runtime-endpoint=/run/containerd/containerd.sock"
            "--node-ip=${devices.${host.name}.address}"
          ];
        };
      };
  };
}
