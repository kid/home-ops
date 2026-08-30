# Reusable sshd aspect. With no addresses it behaves like plain
# `services.openssh.enable = true` (listen everywhere). Passing addresses
# restricts sshd to bind only those — nothing else needs to listen there,
# so no firewall interface-scoping is required on top.
{ lib, ... }:
{
  # `args:` (not `{ addresses ? [ ] }:`) deliberately avoids den's
  # named-args coercion, which would turn this into a context-bound
  # provider instead of a plain callable factory — see
  # den's nix/lib/aspects/types.nix `coercedProviderType`.
  den.aspects.ssh =
    args:
    let
      addresses = args.addresses or [ ];
    in
    {
      nixos = _: {
        services.openssh = {
          enable = true;
          listenAddresses = map (addr: {
            inherit addr;
            port = 22;
          }) addresses;
        };
        # sshd only orders after network.target by default, which is
        # reached before DHCP completes — without this, binding to a
        # DHCP-assigned address can lock SSH out entirely after a reboot.
        systemd.services.sshd = lib.mkIf (addresses != [ ]) {
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
        };
      };
    };
}
