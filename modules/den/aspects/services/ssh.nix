{ lib, ... }:
{
  # `args:` avoids den's coercion of `{ x ? [ ] }:`-style functions into an
  # auto-invoked provider instead of a plain callable aspect factory.
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
        # sshd only orders after network.target by default, which fires
        # before DHCP completes.
        systemd.services.sshd = lib.mkIf (addresses != [ ]) {
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
        };
      };
    };
}
