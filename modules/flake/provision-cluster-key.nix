# nix run .#provision-cluster-key <cluster> — generates an age keypair
# locally, encrypts the private half with sops (binary mode — same
# convention as provision-host-key), and commits both the ciphertext and
# the plaintext public key to secrets/clusters/<cluster>/. This is the
# decryption key sops-operator uses in-cluster (modules/kubernetes/
# sops-operator/default.nix) — age-native, not an SSH key, since
# sops-operator only accepts age/PGP/Vault-transit keys.
#
# modules/flake/nixos-anywhere.nix stages the decrypted private key
# alongside the target host's own SSH key when that host is a k3s node for
# this cluster, delivered via nixos-anywhere --extra-files during install.
{
  perSystem =
    { pkgs, config, ... }:
    {
      packages.provision-cluster-key = pkgs.writeShellApplication {
        name = "provision-cluster-key";
        runtimeInputs = [
          pkgs.age
          pkgs.sops
        ];
        text = ''
          cluster=''${1:?usage: provision-cluster-key <cluster>}
          cluster_dir="secrets/clusters/$cluster"
          sops_file="$cluster_dir/sops-age-key.sops.binary"
          pub_file="$cluster_dir/sops-age-key.pub"

          if [[ -f "$sops_file" ]]; then
            echo "==> $cluster already has a committed key ($sops_file), skipping."
            exit 0
          fi

          mkdir -p "$cluster_dir"
          tmp="$(mktemp -d)"
          trap 'rm -rf "$tmp"' EXIT

          echo "==> Generating age keypair for $cluster..."
          age-keygen -o "$tmp/key" >/dev/null 2>&1
          grep -oP '^# public key: \K.*' "$tmp/key" > "$pub_file"

          echo "==> Encrypting private key with sops..."
          sops --input-type binary --output-type binary --encrypt --output "$sops_file" "$tmp/key"

          echo "==> Committed: $sops_file, $pub_file"
          echo "==> Run 'nix run .#write-sops-config' to add $cluster as an sops recipient."
        '';
      };

      apps.provision-cluster-key = {
        type = "app";
        program = "${config.packages.provision-cluster-key}/bin/provision-cluster-key";
      };
    };
}
