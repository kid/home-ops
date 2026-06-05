{ den, ops, ... }:
{
  den.hosts.x86_64-linux.node0.users.kid = { };

  den.aspects.node0 = {
    includes = [
      (den.batteries.tty-autologin "kid")
      (den.batteries.vm-autologin "kid")
      (ops.disko "/dev/vda")
      ops.boot
      # ops.impermanence
      # ops.k3s
    ];
  };
}
