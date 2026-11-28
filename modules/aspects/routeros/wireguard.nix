# WireGuard remote access on a RouterOS device, plus the IP Cloud DDNS name
# clients use as its endpoint, from the device's routerosInputs.wireguard
# (see modules/fleet/routeros/rb5009.nix). The stack's own resources, through
# the routeros provider configured here: the catalog modules the other
# aspects call each configure their own.
{ lib, ... }:
{
  den.aspects.routeros.wireguard.tofu =
    { routerosDevice, ... }:
    let
      inherit (routerosDevice.aspect.routerosInputs.wireguard) inputs;
      interface = "\${routeros_interface_wireguard.wireguard.name}";
    in
    {
      data.onepassword_item.routeros = {
        vault = inputs.op_vault;
        title = inputs.op_item_routeros;
      };

      provider.routeros.default = {
        hosturl = "\${data.onepassword_item.routeros.url}";
        username = "\${data.onepassword_item.routeros.username}";
        password = "\${data.onepassword_item.routeros.password}";
        insecure = true;
        # System objects are only removed from the state, not the device.
        suppress_syso_del_warn = true;
      };

      resource.routeros_interface_wireguard.wireguard = {
        name = inputs.interface_name;
        inherit (inputs) listen_port;
        mtu = "1420";
      };

      resource.routeros_ip_address.wireguard = {
        inherit (inputs) address;
        inherit interface;
      };

      resource.routeros_interface_list_member.wireguard = {
        inherit interface;
        list = inputs.interface_list;
      };

      resource.routeros_interface_wireguard_peer = lib.mapAttrs' (
        name: peer:
        lib.nameValuePair "wireguard_${name}" {
          inherit interface;
          inherit (peer) public_key;
          allowed_address = [ "${peer.address}/32" ];
          comment = name;
          is_responder = true;
        }
      ) inputs.peers;

      resource.routeros_ip_cloud.wireguard = {
        ddns_enabled = "yes";
        update_time = "false";
      };

      output.wireguard_public_key.value = "\${routeros_interface_wireguard.wireguard.public_key}";

      # The cloudflare stack's CNAME target (modules/aspects/cloudflare/dns.nix).
      output.ip_cloud_dns_name = {
        value = "\${routeros_ip_cloud.wireguard.dns_name}";
        precondition = [
          {
            condition = ''''${routeros_ip_cloud.wireguard.dns_name != null && routeros_ip_cloud.wireguard.dns_name != ""}'';
            error_message = "IP Cloud has not registered a DNS name yet; re-run apply in a minute.";
          }
        ];
      };
    };
}
