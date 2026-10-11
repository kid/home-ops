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
      nixos =
        { config, ... }:
        let
          # sshd only orders after network.target by default, which fires
          # before DHCP completes.
          afterOnline = {
            wants = [ "network-online.target" ];
            after = [ "network-online.target" ];
          };
          socketActivated = config.services.openssh.startWhenNeeded;
        in
        {
          services.openssh = {
            enable = true;
            listenAddresses = map (addr: {
              inherit addr;
              port = 22;
            }) addresses;
          };
          # Whichever unit binds the address: sshd.service has no real
          # definition under socket activation, and sshd.socket is unused
          # without it.
          systemd.sockets.sshd = lib.mkIf (addresses != [ ] && socketActivated) afterOnline;
          systemd.services.sshd = lib.mkIf (addresses != [ ] && !socketActivated) (
            afterOnline
            // {
              # A live switch can restart sshd while networkd re-acquires
              # the address; retry until the bind works instead of giving
              # up at the start limit.
              startLimitIntervalSec = 0;
              serviceConfig.RestartSec = 5;
            }
          );
        };
    };
}
