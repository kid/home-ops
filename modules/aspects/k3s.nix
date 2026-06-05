{
  ops.k3s = {
    nixos =
      { ... }:
      {
        services.k3s = {
          enable = true;
          extraFlags = [
            "--kubelet-arg=register-with-taints=node.cilium.io/agent-not-ready:NoExecute"
          ];
        };
      };
  };
}
