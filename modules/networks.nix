# prd environment's VLANs. cidr is computed downstream
# (environment.networks, in modules/den/schema/environments.nix) from
# environment.cidrBase + vlanId/prefix.
let
  tld = "home.kidibox.net";

  dnsUpstreamServers = [
    "9.9.9.9"
    "149.112.112.112"
  ];
  ntpUpstreamServers = [
    "162.159.200.1"
    "162.159.200.123"
  ];
in
{
  den.networks = {
    Management = {
      environment = "prd";
      vlanId = 99;
      prefix = 16;
      domain = "mgmt.${tld}";
      interfaceLists = [ "MANAGEMENT" ];
      internetAccess = true;
    };

    Servers = {
      environment = "prd";
      vlanId = 10;
      domain = "srv.${tld}";
      internetAccess = true;
    };

    Storage = {
      environment = "prd";
      vlanId = 20;
      domain = "storage.${tld}";
      mtu = 9000;
    };

    # The dev k3s cluster's VLAN, node1's native one. Declared here, not with
    # its cluster like K3s in clusters/prd.nix: node1 lives on it whether or
    # not a cluster runs there. VLANs 42 and 43 stay unused: their /24s are
    # the prd and dev clusters' LoadBalancer pools.
    K3sDev = {
      environment = "prd";
      vlanId = 41;
      domain = "k3s-dev.${tld}";
      internetAccess = true;
    };

    IotLocal = {
      environment = "prd";
      vlanId = 50;
      domain = "iot-local.${tld}";
      internetAccess = false;
    };

    IotInternet = {
      environment = "prd";
      vlanId = 51;
      domain = "iot-internet.${tld}";
      dhcpDnsServers = dnsUpstreamServers;
      dhcpNtpServers = ntpUpstreamServers;
      internetAccess = true;
    };

    Trusted = {
      environment = "prd";
      vlanId = 100;
      domain = "lan.${tld}";
      internetAccess = true;
    };

    Guest = {
      environment = "prd";
      vlanId = 101;
      domain = "iot.${tld}";
      dhcpDnsServers = dnsUpstreamServers;
      dhcpNtpServers = ntpUpstreamServers;
      internetAccess = true;
    };
  };
}
