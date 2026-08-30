# Custom RouterOS group definitions, shared across every device (see
# modules/network/aspects/ros-base.nix for how these get filtered down to
# only the groups each specific device actually needs).
{
  den.groups.external-dns = {
    description = "external-dns integration account";
    policies = [
      "api"
      "read"
      "rest-api"
      "write"
    ];
  };
  den.groups.metrics = {
    description = "mikrotik-exporter metrics account";
    policies = [
      "api"
      "read"
    ];
  };
}
