{ den, ... }:
{
  # A user's terminal baseline on any host, servers and the Mac included. User-included only.
  den.aspects.profiles.cli.includes = [
    (den.batteries.user-shell "zsh")
    den.aspects.shell.zsh
    den.aspects.apps.git
  ];
}
