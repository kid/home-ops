# cecton: a Kanidm-only (SSO) user. Her groups reach only the prd cluster's
# `home` gate and she has no sshKeys, so she gets no host or RouterOS account.
{
  den.users.registry.cecton = {
    groups = [ "home" ];
    displayName = "Cecile";
  };
}
