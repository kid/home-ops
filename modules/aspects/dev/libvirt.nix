# libvirt/QEMU with virt-manager, usable by the privileged user.
_: {
  den.aspects.dev.libvirt = {
    persist.directories = [ "/var/lib/libvirt" ];

    nixos =
      { pkgs, ... }:
      {
        users.privilegedGroups = [ "libvirtd" ];

        environment.systemPackages = with pkgs; [
          virt-manager
          virt-viewer
          (pkgs.writeShellScriptBin "qemu-system-x86_64-uefi" ''
            qemu-system-x86_64 \
              -bios ${pkgs.OVMF.fd}/FV/OVMF.fd \
              "$@"
          '')
        ];

        programs.virt-manager.enable = true;

        virtualisation.libvirtd = {
          enable = true;
          qemu.swtpm.enable = true;
        };
      };
  };
}
