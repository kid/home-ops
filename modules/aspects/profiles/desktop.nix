{ den, ... }:
{
  # Linux graphical desktop: everything vulkan and fw13 share. Host-included only.
  den.aspects.profiles.desktop.includes = with den.aspects; [
    profiles.workstation
    stylix
    desktop.xdg
    desktop.plasma
    desktop.umbriel
    desktop.xremap
    desktop.noctalia-greeter
    desktop.gaming
    desktop.personal
    apps.firefox
    apps.ghostty
    apps.neovim
    apps.wezterm
    ai
    ai.pi
    games.kitten-space-agency
    dev.arduino
    dev.incus
  ];
}
