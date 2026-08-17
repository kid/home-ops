# nix run .#nixos-anywhere-install <host> <ip> [--dry-run] — kexec-based
# remote NixOS install over SSH, directly onto real hardware. The only
# "apply this to real infrastructure" surface this repo's NixOS/cluster work
# introduces; does nothing until run by hand.
#
# Auto-provisions the host's SSH key if it isn't committed yet (see
# modules/flake/provision-host-key.nix), then injects it via --extra-files
# so the host has its real, final identity from first boot. The payload
# lands at persist/etc/ssh/, not etc/ssh/ — nix-community/impermanence
# (modules/den/aspects/impermanence/persist-collector.nix) bind-mounts
# /etc/ssh/ssh_host_ed25519_key FROM /persist/etc/ssh/ssh_host_ed25519_key,
# so that's the real storage location extra-files needs to land on;
# /etc/ssh/... itself is just the bind-mount target, reset on every boot.
#
# Only the host's own SSH identity is a one-shot install-time concern —
# everything else the host needs to decrypt (e.g. a cluster's sops-age key,
# modules/den/aspects/services/k3s/sops-operator.nix) is sops-nix's job,
# declaratively decrypted from committed ciphertext on every activation
# using this same host key, not injected once here.
{
  inputs,
  ...
}:
{
  flake-file.inputs.nixos-anywhere.url = "github:nix-community/nixos-anywhere";

  perSystem =
    {
      system,
      pkgs,
      config,
      ...
    }:
    {
      packages.nixos-anywhere-install = pkgs.writeShellApplication {
        name = "nixos-anywhere-install";
        # util-linux: nixos-anywhere's own closure has no `setsid` at
        # all (confirmed: absent from its wrapped PATH) — it shells out
        # to whatever `setsid --wait`-capable binary is ambient, and
        # errors ("no setsid command respecting --wait found") if none
        # is on PATH.
        runtimeInputs = [
          inputs.nixos-anywhere.packages.${system}.default
          pkgs.util-linux
          pkgs.sops
          config.packages.provision-host-key
        ];
        text = ''
          dry_run=false
          args=()
          for arg in "$@"; do
            if [[ "$arg" == "--dry-run" ]]; then
              dry_run=true
            else
              args+=("$arg")
            fi
          done
          set -- "''${args[@]+"''${args[@]}"}"

          host=''${1:?usage: nixos-anywhere-install <host> <ssh-target, e.g. root@10.0.40.10> [--dry-run]}
          target=''${2:?usage: nixos-anywhere-install <host> <ssh-target, e.g. root@10.0.40.10> [--dry-run]}

          sops_file="secrets/hosts/$host/ssh_host_ed25519_key.sops"
          pub_file="secrets/hosts/$host/ssh_host_ed25519_key.pub"

          if [[ ! -f "$sops_file" ]]; then
            echo "==> No committed SSH host key for $host, provisioning one..."
            provision-host-key "$host"
          fi

          tmp="$(mktemp -d)"
          trap 'rm -rf "$tmp"' EXIT

          echo "==> Decrypting SSH host key for $host..."
          install -d -m755 "$tmp/persist/etc/ssh"
          sops --decrypt --input-type binary --output-type binary "$sops_file" > "$tmp/persist/etc/ssh/ssh_host_ed25519_key"
          chmod 600 "$tmp/persist/etc/ssh/ssh_host_ed25519_key"
          cp "$pub_file" "$tmp/persist/etc/ssh/ssh_host_ed25519_key.pub"
          chmod 644 "$tmp/persist/etc/ssh/ssh_host_ed25519_key.pub"

          nixos_anywhere_args=(--flake ".#$host" "$target" --extra-files "$tmp")

          if [[ "$dry_run" == true ]]; then
            echo "[DRY RUN] Would run: nixos-anywhere ''${nixos_anywhere_args[*]}"
            exit 0
          fi

          echo "==> Installing NixOS host '$host' onto $target via nixos-anywhere..."
          nixos-anywhere "''${nixos_anywhere_args[@]}"
        '';
      };

      apps.nixos-anywhere-install = {
        type = "app";
        program = "${config.packages.nixos-anywhere-install}/bin/nixos-anywhere-install";
      };
    };
}
