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

    # VLAN 42 stays unused: its /24 is prd's LoadBalancer pool.

    IotLocal = {
      environment = "prd";
      vlanId = 50;
      domain = "iot-local.${tld}";
      internetAccess = false;
    };

    # Router DNS, not upstream: coreelec resolves plex.kidibox.net to the
    # apps gateway through the router's external-dns records.
    IotInternet = {
      environment = "prd";
      vlanId = 51;
      domain = "iot-internet.${tld}";
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
