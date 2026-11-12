# The cluster a k3s node belongs to, set per host as
# `settings.k3s.clusterName` and read by every den.aspects.k3s.* aspect. A
# host is a k3s node when it includes den.aspects.k3s.node-base (through
# k3s.server or k3s.agent); flake tooling (colmena tags, kube-login,
# .sops.yaml) finds a cluster's members the same way.
{ lib, ... }:
{
  den.aspects.k3s.settings.clusterName = lib.mkOption {
    type = lib.types.str;
    description = "Name of the den.clusters entry this k3s node belongs to";
  };
}
