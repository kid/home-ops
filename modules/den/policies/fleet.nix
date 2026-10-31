# Fleet topology policies.
#
# Wires the scope tree: flake -> fleet -> environment -> {network,
# routerosDevice, cluster, host}. Adapted from nix-config's modules/den/policies/
# fleet.nix (itself the model nixopslab's environment.nix points at); hosts
# follow den's "Access Control & Environments" guide, resolved under their
# environment instead of den's default flake-system walk.
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

  # environment -> routerosDevices: walk den.routerosDevices whose environment matches.
  den.policies.env-to-routeros-devices =
    { environment, ... }:
    den.routerosDevices
    |> builtins.attrNames
    |> lib.concatMap (
      routerosDeviceName:
      let
        routerosDeviceCfg = den.routerosDevices.${routerosDeviceName};
      in
      lib.optionals (routerosDeviceCfg.environment == environment.name) [
        (resolve.to "routerosDevice" { routerosDevice = routerosDeviceCfg; })
      ]
    );

  # environment -> networks: walk den.networks whose environment matches.
  # A future entity kind (e.g. a k3s cluster) could contribute its own VLAN
  # the same way, by adding another policy to den.schema.environment.includes
  # that also does `resolve.to "network" {...}` — no edit needed here.
  den.policies.env-to-networks =
    { environment, ... }:
    den.networks
    |> builtins.attrNames
    |> lib.concatMap (
      networkName:
      let
        networkCfg = den.networks.${networkName};
      in
      lib.optionals (networkCfg.environment == environment.name) [
        (resolve.to "network" { network = networkCfg; })
      ]
    );

  # environment -> clusters: walk den.clusters whose environment matches.
  den.policies.env-to-clusters =
    { environment, ... }:
    den.clusters
    |> builtins.attrNames
    |> lib.concatMap (
      clusterName:
      let
        clusterCfg = den.clusters.${clusterName};
      in
      lib.optionals (clusterCfg.environment == environment.name) [
        (resolve.to "cluster" { cluster = clusterCfg; })
      ]
    );

  # environment -> hosts: resolve and instantiate (nixosConfigurations) every
  # den.hosts entry of this environment. Replaces den's system-to-os-outputs,
  # so host scopes see `environment`. Test-only hosts (intoAttr = [ ]) are
  # skipped before their environment is read.
  den.policies.env-to-hosts =
    { environment, ... }:
    den.hosts
    |> builtins.attrValues
    |> lib.concatMap builtins.attrValues
    |> lib.concatMap (
      host:
      lib.optionals (host.intoAttr != [ ] && host.environment == environment.name) [
        (resolve.to "host" { inherit host; })
        (den.lib.policy.instantiate host)
      ]
    );

  den.schema.flake.includes = [ den.policies.to-fleet ];
  den.schema.fleet.includes = [ den.policies.fleet-to-envs ];
  den.schema.environment.includes = [
    den.policies.env-to-routeros-devices
    den.policies.env-to-networks
    den.policies.env-to-clusters
    den.policies.env-to-hosts
  ];
  den.schema.flake-system.excludes = [ den.policies.system-to-os-outputs ];
}
