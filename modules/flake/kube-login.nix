# kube-login <cluster> — adds a kubectl context for a den.clusters entry that logs in through
# Kanidm with kubelogin (public client, PKCE), using the server name, issuer and client ID from
# the cluster's methods.kubeLogin (modules/kubernetes/apiserver/default.nix). The
# API server CA comes from the cluster's first node over SSH. A cluster without kubeLogin is
# not offered.
#
# - The context runs `kubectl oidc-login` at use time: needs `kubectl-oidc_login` (package
#   kubelogin-oidc, in the devshell) on PATH.
# - `groups_name` makes Kanidm put plain group names in the `groups` claim; `groups` would
#   send SPNs (`<group>@<domain>`), which match no RoleBinding.
# - The username is `<issuer>#<Kanidm UUID>`.
# - If Kanidm is down, use the admin kubeconfig on the node: /etc/rancher/k3s/k3s.yaml.
{
  config,
  lib,
  ...
}:
let
  clusters = lib.filterAttrs (_: cluster: cluster.methods ? kubeLogin) config.den.clusters;

  allHosts = lib.foldl' (acc: system: acc // (config.den.hosts.${system} or { })) { } config.systems;

  # The first host of the cluster (host.k3s.clusterName), at its address on the cluster network.
  nodeAddress =
    name:
    let
      members = builtins.filter (host: (allHosts.${host}.k3s.clusterName or null) == name) (
        builtins.attrNames allHosts
      );
    in
    config.den.devices.${builtins.head members}.address;

  caseArm =
    name: cluster:
    let
      login = cluster.methods.kubeLogin;
    in
    ''
      ${lib.escapeShellArg name})
        node=${lib.escapeShellArg (nodeAddress name)}
        server=${lib.escapeShellArg "https://${login.server}:6443"}
        issuer=${lib.escapeShellArg login.issuerUrl}
        client_id=${lib.escapeShellArg login.clientId}
        group=${lib.escapeShellArg login.group}
        ;;
    '';

  known = lib.concatStringsSep " " (builtins.attrNames clusters);
in
{
  perSystem =
    { pkgs, config, ... }:
    {
      packages.kube-login = pkgs.writeShellApplication {
        name = "kube-login";
        runtimeInputs = [
          pkgs.kubectl
          pkgs.openssh
        ];
        text = ''
          cluster=''${1:?usage: kube-login <cluster> (known: ${known})}

          case "$cluster" in
          ${lib.concatStrings (lib.mapAttrsToList caseArm clusters)}
          *)
            echo "kube-login: unknown cluster '$cluster' (known: ${known})" >&2
            exit 1
            ;;
          esac

          ca=$(mktemp)
          trap 'rm -f "$ca"' EXIT

          echo "==> Fetching the API server CA from $node..."
          ssh "$node" sudo cat /var/lib/rancher/k3s/server/tls/server-ca.crt >"$ca"

          kubectl config set-cluster "$cluster" \
            --server="$server" \
            --certificate-authority="$ca" \
            --embed-certs=true

          kubectl config set-credentials "$cluster-oidc" \
            --exec-api-version=client.authentication.k8s.io/v1 \
            --exec-interactive-mode=Never \
            --exec-command=kubectl \
            --exec-arg=oidc-login \
            --exec-arg=get-token \
            --exec-arg=--oidc-issuer-url="$issuer" \
            --exec-arg=--oidc-client-id="$client_id" \
            --exec-arg=--oidc-extra-scope=groups_name

          kubectl config set-context "$cluster" --cluster="$cluster" --user="$cluster-oidc"
          kubectl config use-context "$cluster"

          echo "==> Context $cluster ready. 'kubectl auth whoami' opens Kanidm in your browser and should list the group $group."
        '';
      };

      apps.kube-login = {
        type = "app";
        program = "${config.packages.kube-login}/bin/kube-login";
      };
    };
}
