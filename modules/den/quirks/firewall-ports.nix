# Host-level daemon ports (SSH, apiserver, kubelet) aren't emitted here since den doesn't deliver a host-scope quirk to a cluster-scope consumer.
{
  den.quirks.firewall-ports.description = "Port requirements for node1's Cilium host firewall, contributed by cluster-scoped Kubernetes app aspects";
}
