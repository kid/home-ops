# nix run .#provision-host-key <host> — generates an ed25519 SSH host key
# locally, encrypts the private half with sops (binary mode — the payload is
# raw PEM bytes, not YAML/JSON structured data), and commits the ciphertext,
# the plaintext public key, and its age-converted form to
# secrets/hosts/<host>/. Uses this repo's existing sops recipients
# (kid-vulkan/kid-fw13, .sops.yaml) — encryption only needs their public
# halves, already present in .sops.yaml, so this needs no new key material
# of its own to run.
#
# age-pub exists because sops's raw "ssh-ed25519 ..." recipients and
# sops-nix's host-side decrypt derive different X25519 keys from the same
# SSH key — sops-nix needs the age1... form as its recipient.
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
          pkgs.ssh-to-age
        ];
        text = ''
          host=''${1:?usage: provision-host-key <host>}
          host_dir="secrets/hosts/$host"
          sops_file="$host_dir/ssh_host_ed25519_key.sops"
          pub_file="$host_dir/ssh_host_ed25519_key.pub"
          age_pub_file="$host_dir/ssh_host_ed25519_key.age-pub"

          if [[ -f "$sops_file" ]]; then
            echo "==> $host already has a committed key ($sops_file), skipping generation."
          else
            mkdir -p "$host_dir"
            tmp="$(mktemp -d)"
            trap 'rm -rf "$tmp"' EXIT

            echo "==> Generating ed25519 host key for $host..."
            ssh-keygen -t ed25519 -N "" -f "$tmp/key" -C "root@$host" >/dev/null

            echo "==> Encrypting private key with sops..."
            sops --input-type binary --output-type binary --encrypt --output "$sops_file" "$tmp/key"

            cp "$tmp/key.pub" "$pub_file"

            echo "==> Committed: $sops_file, $pub_file"
          fi

          if [[ ! -f "$age_pub_file" ]]; then
            echo "==> Deriving age public key for $host..."
            ssh-to-age -i "$pub_file" > "$age_pub_file"
            echo "==> Committed: $age_pub_file"
          fi

          echo "==> Run 'nix run .#write-sops-config' to add $host as an sops recipient."
        '';
      };

      apps.provision-host-key = {
        type = "app";
        program = "${config.packages.provision-host-key}/bin/provision-host-key";
      };
    };
}
