# Fleet topology policies.
#
# Wires the scope tree: flake -> fleet -> environment -> {network, device,
# cluster}. Adapted from nix-config's modules/den/policies/fleet.nix (itself
# the model nixopslab's environment.nix points at), dropping the
# user-access/grant machinery — not needed for a fleet of RouterOS devices —
# and walking den.devices/den.networks instead of den.hosts.
{
  lib,
  den,
  config,
  ...
}:
let
  inherit (den.lib.policy) resolve;

  inherit (config.den) environments;
in
{
  # flake -> fleet: single fleet entity (fires at flake scope).
  den.policies.to-fleet = _: [
    (resolve.to "fleet" {
      fleet = {
        name = "fleet";
      };
    })
  ];

  # fleet -> environments: fan out per registered environment.
  den.policies.fleet-to-envs =
    _:
    lib.mapAttrsToList (
      _: env:
      resolve.to "environment" {
        environment = env;
      }
    ) environments;

  # environment -> devices: walk den.devices whose environment matches.
  den.policies.env-to-devices =
    { environment, ... }:
    lib.concatMap (
      deviceName:
      let
        deviceCfg = den.devices.${deviceName};
      in
      lib.optionals (deviceCfg.environment == environment.name) [
        (resolve.to "device" { device = deviceCfg; })
      ]
    ) (builtins.attrNames den.devices);

  # environment -> networks: walk den.networks whose environment matches.
  # A future entity kind (e.g. a k3s cluster) could contribute its own VLAN
  # the same way, by adding another policy to den.schema.environment.includes
  # that also does `resolve.to "network" {...}` — no edit needed here.
  den.policies.env-to-networks =
    { environment, ... }:
    lib.concatMap (
      networkName:
      let
        networkCfg = den.networks.${networkName};
      in
      lib.optionals (networkCfg.environment == environment.name) [
        (resolve.to "network" { network = networkCfg; })
      ]
    ) (builtins.attrNames den.networks);

  # environment -> clusters: walk den.clusters whose environment matches.
  den.policies.env-to-clusters =
    { environment, ... }:
    lib.concatMap (
      clusterName:
      let
        clusterCfg = den.clusters.${clusterName};
      in
      lib.optionals (clusterCfg.environment == environment.name) [
        (resolve.to "cluster" { cluster = clusterCfg; })
      ]
    ) (builtins.attrNames den.clusters);

  den.schema.flake.includes = [ den.policies.to-fleet ];
  den.schema.fleet.includes = [ den.policies.fleet-to-envs ];
  den.schema.environment.includes = [
    den.policies.env-to-devices
    den.policies.env-to-networks
    den.policies.env-to-clusters
  ];
}
