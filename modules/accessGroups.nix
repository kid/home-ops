# Access-control group graph (schema: modules/den/schema/accessGroups.nix).
{
  den.accessGroups = {
    admins = {
      description = "Log in anywhere";
      labels = [
        "oauth-grant"
        "mfa"
      ];
    };
    wheel = {
      labels = [ "posix" ];
      members = [ "admins" ];
    };
    # RouterOS built-in group.
    full = {
      labels = [ "routeros" ];
      members = [ "admins" ];
    };
  };
}
