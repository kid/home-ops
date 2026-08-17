# nix run .#provision-host-key <host> — generates an ed25519 SSH host key
# locally, encrypts the private half with sops (binary mode — the payload is
# raw PEM bytes, not YAML/JSON structured data), and commits both the
# ciphertext and the plaintext public key to secrets/hosts/<host>/. Uses this
# repo's existing sops recipients (kid-vulkan/kid-fw13, .sops.yaml) —
# encryption only needs their public halves, already present in .sops.yaml,
# so this needs no new key material of its own to run.
#
# modules/flake/nixos-anywhere.nix consumes the committed key at install
# time, injecting it via nixos-anywhere --extra-files so the host has its
# real, final SSH identity from first boot — no first-boot keygen, no
# post-boot ssh-keyscan capture step.
{
  perSystem =
    { pkgs, config, ... }:
    {
      packages.provision-host-key = pkgs.writeShellApplication {
        name = "provision-host-key";
        runtimeInputs = [
          pkgs.openssh
          pkgs.sops
        ];
        text = ''
          host=''${1:?usage: provision-host-key <host>}
          host_dir="secrets/hosts/$host"
          sops_file="$host_dir/ssh_host_ed25519_key.sops.json"
          pub_file="$host_dir/ssh_host_ed25519_key.pub"

          if [[ -f "$sops_file" ]]; then
            echo "==> $host already has a committed key ($sops_file), skipping."
            exit 0
          fi

          mkdir -p "$host_dir"
          tmp="$(mktemp -d)"
          trap 'rm -rf "$tmp"' EXIT

          echo "==> Generating ed25519 host key for $host..."
          ssh-keygen -t ed25519 -N "" -f "$tmp/key" -C "root@$host" >/dev/null

          echo "==> Encrypting private key with sops..."
          sops --input-type binary --output-type binary --encrypt --output "$sops_file" "$tmp/key"

          cp "$tmp/key.pub" "$pub_file"

          echo "==> Committed: $sops_file, $pub_file"
          echo "==> Run 'nix run .#write-sops-config' to add $host as an sops recipient."
        '';
      };

      apps.provision-host-key = {
        type = "app";
        program = "${config.packages.provision-host-key}/bin/provision-host-key";
      };
    };
}
