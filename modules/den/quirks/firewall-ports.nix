# Port requirements for node1's Cilium host firewall, contributed by
# cluster-scoped Kubernetes app aspects ({ cluster, ... }: [...]). Fragment
# shape: { port; protocol; description; from; }. Collected onto the
# `cluster` entity (modules/den/policies/firewall-ports.nix) and consumed
# inside modules/den/aspects/kubernetes/cilium/host-firewall.nix's
# `k8s-manifests` content.
#
# NixOS host-level daemon ports (SSH, kube-apiserver, kubelet) aren't
# collected through this quirk — den doesn't reliably deliver a
# host-scope-emitted quirk to a cluster-scope consumer. They're declared
# directly in host-firewall.nix instead, same scope as the consumer.
{
  den.quirks.firewall-ports.description = "Port requirements for node1's Cilium host firewall, contributed by cluster-scoped Kubernetes app aspects";
}
