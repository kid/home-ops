{ den, ... }:
{
  # Headless fleet host: shared base, srvos server, static networking from den.devices.
  den.aspects.profiles.server.includes = with den.aspects; [
    base
    server
    host-network
  ];
}
