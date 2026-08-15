# Folds OpenBao's Terraform stacks into config.flake.terragruntStacks
# (modules/terragrunt/collect.nix's home, though this policy is defined
# alongside it rather than in that file, to keep collect.nix's existing
# routerosDevice-only logic untouched) — modules/terragrunt/devshell.nix's
# existing write-terragrunt/checks.terragrunt machinery renders and checks
# both leaves below with no further generalization needed.
#
# Both leaves are produced by ONE den.lib.policy.instantiate call, not two:
# den's intoAttr merge only supports one instantiate spec per exact target
# path (two policies both targeting `terragruntStacks.prd` silently drops
# all but the last — confirmed the hard way, via `nix run .#write-manifests`
# printing "evaluation warning: den: multiple instantiate specs target
# flake.terragruntStacks.prd on unknown; keeping last"). One combined
# instantiate call sidesteps that entirely.
#
# - openbao-config: one-time cluster bootstrap (KV v2 mount, AppRole auth
#   backend + role + read policy for ESO, the resulting k8s Secret) — fixed
#   content, not derived from any aspect's collected data.
# - openbao-items: per-app secrets (modules/kubernetes/_secrets-lib.nix's
#   mkOpenBaoItem, collected via cluster-to-openbao-items in
#   modules/den/policies/cluster.nix) — one combined leaf per cluster, since
#   every app's secrets are individually small and share one Terraform
#   state. Must be applied *after* openbao-config (creates the KV mount this
#   one writes into) — not encoded as a Terragrunt `dependencies` block,
#   since that mechanism (relPathToRouterosDeviceBase in
#   modules/terragrunt/devshell.nix) is RouterOS-device-path-shaped;
#   documented here as a manual apply-order requirement instead.
{
  config,
  lib,
  den,
  hcl,
  ...
}:
{
  den.policies.cluster-to-openbao-terragrunt =
    { cluster, ... }:
    [
      (den.lib.policy.instantiate {
        name = "${cluster.name}-openbao-terragrunt";
        class = "openbao-items";
        instantiate =
          _:
          let
            items = config.flake.openbaoItems.${cluster.name} or [ ];
            address = "http://openbao.kidibox.net:8200";
            rootToken = hcl.raw "local.openbao_init.root_token";
          in
          {
            openbao-config = {
              stack = "openbao-config";
              localModule = "openbao-config";
              dependsOn = [ ];
              sopsFile = "secrets/prd/openbao-init.sops.yaml";
              sopsLocalName = "openbao_init";
              inputs = {
                inherit address;
                root_token = rootToken;
                kv_mount = "secret";
                approle_role_name = "external-secrets";
                approle_role_id = "external-secrets";
                secret_namespace = "external-secrets";
                secret_name = "openbao-approle";
              };
            };
          }
          // lib.optionalAttrs (items != [ ]) {
            openbao-items = {
              stack = "openbao-items";
              localModule = "openbao-items";
              dependsOn = [ ];
              sopsFile = "secrets/prd/openbao-init.sops.yaml";
              sopsLocalName = "openbao_init";
              inputs = {
                inherit address;
                root_token = rootToken;
                kv_mount = "secret";
                inherit items;
              };
            };
          };
        intoAttr = [
          "terragruntStacks"
          cluster.name
        ];
      })
    ];

  den.schema.cluster.includes = [ den.policies.cluster-to-openbao-terragrunt ];
}
