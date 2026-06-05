{
  ops.ssh-keys = {
    description = "Provision authorized SSH keys from user registry";
    includes = [
      (
        { host, user }:
        {
          name = "ssh-keys${user.name}@${host.name}";
          nixos.users.users.${user.userName}.openssh.authorizedKeys = user.sshKeys;
        }
      )
    ];
  };
}
