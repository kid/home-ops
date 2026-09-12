{ den, ... }:
{
  den.environments.dev = {
    domain = "dev.kidibox.net";
    cidrBase = "10.200.0.0/16";
  };

  den.networks.Dev = {
    environment = "dev";
    vlanId = 1;
    domain = "dev.kidibox.net";
  };

  den.clusters.dev = {
    environment = "dev";
    network = "Dev";
    domain = "dev.kidibox.net";

    networks = {
      pods = {
        cidr = "172.30.0.0/16";
        description = "dev k3s pod overlay network";
      };
      services = {
        cidr = "172.31.0.0/16";
        description = "dev k3s service overlay network";
        assignments.coredns = "172.31.0.10";
      };
    };

    bgp.localAsn = 4200000000;

    letsencrypt.staging = true;

    nixidy = {
      repository = "https://github.com/kid/home-ops.git";
      branch = "dev";
      rootPath = "manifests/dev";
    };
  };

  den.aspects.dev.includes = with den.aspects.kubernetes; [
    gateway-api-crds
    envoy-gateway
    cert-manager
    coredns
    argocd
    sops-operator
  ];
}
