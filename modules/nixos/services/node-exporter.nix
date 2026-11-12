# node-exporter on the hosts outside the cluster (the k3s nodes run the
# chart's DaemonSet). Emits the `node-exporter-targets` quirk, from which
# each cluster's vmagent scrapes the host's primary address through the
# router (modules/kubernetes/victoria-metrics/default.nix), and the RouterOS
# forward rule that lets it. Pods leave masqueraded behind their node's
# address, so the port is open to the VLANs of the clusters in the host's
# environment.
{ config, lib, ... }:
let
  port = 9100;

  addressOf = host: config.den.devices.${host.name}.address;

  scraperNetworksOf =
    host:
    config.den.clusters
    |> lib.attrValues
    |> lib.filter (c: c.environment == host.environment)
    |> map (c: c.network);
in
{
  den.aspects.node-exporter = {
    node-exporter-targets =
      { host, ... }:
      {
        hostname = host.name;
        address = addressOf host;
        inherit port;
      };

    firewall =
      { host, ... }:
      map (network: {
        inherit network;
        forward = [
          {
            action = "accept";
            dst_address = addressOf host;
            dst_port = port;
            protocol = "tcp";
            comment = "Allow access to ${host.name} from ${network} for node-exporter";
          }
        ];
      }) (scraperNetworksOf host);

    nixos =
      { host, ... }:
      let
        scraperCidrs =
          scraperNetworksOf host
          |> map (network: config.den.environments.${host.environment}.networks.${network}.cidr);
      in
      {
        services.prometheus.exporters.node = {
          enable = true;
          inherit port;
          openFirewall = true;
          firewallRules = ''ip saddr { ${lib.concatStringsSep ", " scraperCidrs} } tcp dport ${toString port} accept comment "node-exporter"'';
        };
      };
  };
}
