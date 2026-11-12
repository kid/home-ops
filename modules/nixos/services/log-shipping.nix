# Ships the journal of the hosts outside the cluster to VictoriaLogs:
# systemd-journal-upload posts it to the vlagent relay on its fixed
# LoadBalancer IP (modules/kubernetes/victoria-metrics/vlagent-hosts.nix),
# which accepts nothing but ingestion. Emits the `log-shippers` quirk, from
# which that relay admits the host's address, and the RouterOS forward rule
# from the host's VLAN to the relay.
{ config, lib, ... }:
let
  # vlagent's default HTTP ingestion port.
  port = 9429;

  # The cluster in the host's environment that pins the relay's address.
  relayAddressOf =
    host:
    let
      addresses =
        config.den.clusters
        |> lib.attrValues
        |> lib.filter (c: c.environment == host.environment)
        |> lib.concatMap (c: lib.optional (c.networks ? loadBalancer) c.networks.loadBalancer.assignments)
        |> lib.concatMap (a: lib.optional (a ? vlagent-hosts) a.vlagent-hosts);
    in
    if lib.length addresses == 1 then
      lib.head addresses
    else
      throw "log-shipping: ${host.name} needs exactly one cluster in ${host.environment} with a vlagent-hosts LoadBalancer assignment, found ${toString (lib.length addresses)}";

  deviceOf = host: config.den.devices.${host.name};
in
{
  den.aspects.log-shipping = {
    log-shippers =
      { host, ... }:
      {
        hostname = host.name;
        inherit (deviceOf host) address;
      };

    firewall =
      { host, ... }:
      let
        inherit ((lib.head (deviceOf host).interfaces)) network;
      in
      [
        {
          inherit network;
          forward = [
            {
              action = "accept";
              dst_address = relayAddressOf host;
              dst_port = port;
              protocol = "tcp";
              comment = "Allow ${host.name} to ship its journal to VictoriaLogs";
            }
          ];
        }
      ];

    # The upload cursor (--save-state), under DynamicUser's /var/lib/private:
    # without it, a reboot uploads the whole persisted journal again.
    cache.directories = [
      {
        directory = "/var/lib/private";
        mode = "0700";
      }
    ];

    nixos =
      { host, ... }:
      {
        services.journald.upload = {
          enable = true;
          settings.Upload = {
            URL = "http://${relayAddressOf host}:${toString port}/insert/journald";
            Compression = "zstd";
          };
        };
      };
  };
}
