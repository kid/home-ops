# Ports a cluster's Cilium host firewall (modules/kubernetes/cilium/host-firewall.nix)
# opens on its nodes. Fragment shape: { port; protocol; description; from ? [ <entity> ];
# fromCIDR ? [ <cidr> ]; endPort ?; controlPlane ? false; }. Contributed by the
# cluster's own app aspects, or by one of its k3s hosts for a service the host
# itself runs (k3s-prd-0's NFS server), which adds `cluster` (its
# settings.k3s.clusterName): modules/den/policies/firewall-ports.nix keeps only
# the cluster's own. The policy has no per-node selector: a host's port opens
# on every node of its cluster. SSH, the apiserver and the kubelet are
# host-firewall.nix's own.
{
  den.quirks.firewall-ports.description = "Port requirements for a cluster's Cilium host firewall, contributed by its app aspects and its k3s hosts";
}
