# Quirk metadata registration. Port requirements for node1's Cilium host
# firewall, contributed by cluster-scoped Kubernetes app aspects
# ({ cluster, ... }: [...]). Fragment shape: { port; protocol; description;
# from; }. Collected onto the `cluster` entity (modules/den/policies/
# firewall-ports.nix) and consumed directly inside a `k8s-manifests`
# class-content function (den's own class content gets automatic quirk-arg
# resolution — den's own test suite, templates/ci/modules/public-api/
# pipes.nix's test-pipe-discriminator, is the proof this pattern works).
#
# NixOS host-level daemon ports (SSH, kube-apiserver, kubelet) are NOT
# collected through this quirk, despite being conceptually the same kind of
# fragment — den does not reliably deliver a host-scope-emitted quirk to a
# cluster-scope consumer (confirmed empirically, see modules/den/policies/
# firewall-ports.nix's own comment for the full account). They're declared
# directly in modules/den/clusters/prd.nix instead, same scope as this
# consumer.
{
  den.quirks.firewall-ports.description = "Port requirements for node1's Cilium host firewall, contributed by cluster-scoped Kubernetes app aspects";
}
