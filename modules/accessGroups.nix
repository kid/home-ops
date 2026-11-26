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
    home = {
      description = "Household apps on the cluster";
      labels = [
        "oauth-grant"
        "mfa"
      ];
      members = [ "admins" ];
    };
    media = {
      description = "Media apps on the cluster";
      labels = [
        "oauth-grant"
        "mfa"
      ];
      members = [ "admins" ];
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
    # The work Mac's gate (kid/nixfiles-work). No labels, no members: the
    # Kanidm, OAuth and RouterOS consumers ignore it, and admins aren't in it.
    work = {
      description = "Log in on work machines";
    };
  };
}
