# /tmp on tmpfs. Ported verbatim from nixopslab's
# modules/den/aspects/impermanence/tmpfs.nix. Separate from the main
# impermanence aspect since not every host wants /tmp on tmpfs.
{
  den.aspects.impermanence.tmpfs.nixos = {
    boot.tmp = {
      useTmpfs = true;
      cleanOnBoot = true;
    };
  };
}
