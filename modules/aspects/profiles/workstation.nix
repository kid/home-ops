{ den, ... }:
{
  # Personal machine, Linux or Mac: included by profiles.desktop on Linux, by the user on the Mac.
  den.aspects.profiles.workstation.includes = with den.aspects; [
    base
    workstation
    users.hm-defaults
  ];
}
