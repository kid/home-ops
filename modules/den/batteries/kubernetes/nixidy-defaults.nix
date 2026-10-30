# Shared nixidy defaults, injected into every cluster's k8s-manifests scope.
# Not a collector itself — modules/den/policies/cluster.nix's
# cluster-to-nixidy policy assembles this aspect's content together with
# each app aspect's (modules/den/aspects/kubernetes/*/default.nix) into the real
# nixidy environment.
_:
let
  nixidyDefaultsAspect = {
    name = "nixidy/defaults";
    k8s-manifests =
      { cluster, environment, ... }:
      {
        lib,
        config,
        pkgs,
        generators,
        ...
      }:
      let
        # The app holding every Namespace and every other app's Flux
        # Kustomization, applied by the FluxInstance's root sync
        # (modules/den/aspects/kubernetes/flux/default.nix).
        appsName = config.nixidy.appOfApps.name;
        childApps = lib.filter (name: name != appsName) config.nixidy.publicApps;
        # kube-system/default are pre-existing, cluster-critical namespaces —
        # never let the apps Kustomization own them.
        systemNamespaces = [
          "kube-system"
          "default"
        ];
        # Every app's own namespace is created here instead of in its own
        # manifest set, so two apps sharing a namespace (e.g. cert-manager +
        # trust-manager) don't both own the same object. Apps don't set
        # createNamespace themselves — this replaces nixidy's own per-app
        # handling of it.
        namespacesToCreate = lib.unique (
          lib.filter (ns: !(builtins.elem ns systemNamespaces)) (
            map (app: app.namespace) (lib.attrValues config.applications)
          )
        );

        helmLabels = [
          "app.kubernetes.io/managed-by"
          "app.kubernetes.io/version"
          "helm.sh/chart"
        ];
        stripHelmLabels =
          manifest:
          let
            stripped = lib.kube.removeLabels helmLabels manifest;
          in
          # removeLabels leaves a monitor's selector alone, so it would
          # still select on the labels just removed from its target.
          if
            builtins.elem (manifest.kind or "") [
              "ServiceMonitor"
              "PodMonitor"
            ]
            && stripped ? spec.selector.matchLabels
          then
            lib.updateManyAttrsByPath [
              {
                path = [
                  "spec"
                  "selector"
                  "matchLabels"
                ];
                update = old: removeAttrs old helmLabels;
              }
            ] stripped
          else
            stripped;

        # Flux applies a Helm hook like any other object, so a delete, test or
        # rollback hook would run on the next sync: those must be disabled in
        # the chart's values. Install/upgrade hooks become plain objects. A
        # Job's template is immutable, so Flux recreates it when that changes;
        # with no TTL it stays Complete instead of being recreated every sync.
        hookAnnotations = [
          "helm.sh/hook"
          "helm.sh/hook-weight"
          "helm.sh/hook-delete-policy"
        ];
        installHooks = [
          "pre-install"
          "post-install"
          "pre-upgrade"
          "post-upgrade"
        ];
        unhook =
          manifest:
          let
            hook = manifest.metadata.annotations."helm.sh/hook";
            annotations = removeAttrs manifest.metadata.annotations hookAnnotations;
            plain = manifest // {
              metadata =
                removeAttrs manifest.metadata [ "annotations" ]
                // lib.optionalAttrs (annotations != { }) { inherit annotations; };
            };
          in
          if !(manifest ? metadata.annotations."helm.sh/hook") then
            manifest
          else if !(lib.all (h: builtins.elem (lib.trim h) installHooks) (lib.splitString "," hook)) then
            throw "${manifest.kind}/${manifest.metadata.name} is a Helm ${hook} hook: disable it in the chart's values"
          else if manifest.kind == "Job" then
            lib.recursiveUpdate (plain // { spec = removeAttrs plain.spec [ "ttlSecondsAfterFinished" ]; }) {
              metadata.annotations."kustomize.toolkit.fluxcd.io/force" = "Enabled";
            }
          else
            plain;
      in
      {
        # den's collision-validator writes to config.warnings; nixidy's own
        # module system doesn't declare that NixOS-ism by default.
        options.warnings = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };

        config.applications.${appsName} = {
          resources = {
            # nixidy always renders an Argo CD Application per app here.
            applications = lib.mkForce { };

            namespaces = lib.genAttrs namespacesToCreate (_: {
              metadata.annotations."kustomize.toolkit.fluxcd.io/prune" = "disabled";
            });

            kustomizations = lib.genAttrs childApps (
              name:
              let
                app = config.applications.${name};
              in
              {
                spec = {
                  path = "./${config.nixidy.target.rootPath}/${app.output.path}";
                  # The FluxInstance's sync names its GitRepository after its namespace.
                  sourceRef = {
                    kind = "GitRepository";
                    name = "flux-system";
                  };
                  interval = "10m";
                  retryInterval = "1m";
                  timeout = "5m";
                  prune = true;
                  wait = true;
                  dependsOn = lib.mkIf (app.flux.dependsOn != [ ]) (
                    map (dep: { name = dep; }) (lib.unique app.flux.dependsOn)
                  );
                };
              }
            );
          };

          assertions = lib.concatMap (
            name:
            map (dep: {
              assertion = builtins.elem dep childApps;
              message = "flux.dependsOn of ${name} names ${dep}, which is not an application";
            }) config.applications.${name}.flux.dependsOn
          ) childApps;
        };

        config.nixidy = {
          env = lib.mkDefault "${environment.name}-${cluster.name}";
          target = {
            repository = lib.mkDefault cluster.nixidy.repository;
            branch = lib.mkDefault cluster.nixidy.branch;
            rootPath = lib.mkDefault cluster.nixidy.rootPath;
          };
          appOfApps.namespace = "flux-system";
          extraFiles."README.md".text = "Generated by nixidy — do not edit by hand.\n";
          applicationImports = [
            (generators.fromCRDModule {
              name = "flux";
              src = pkgs.fetchFromGitHub {
                owner = "fluxcd";
                repo = "kustomize-controller";
                # renovate: datasource=github-releases depName=fluxcd/kustomize-controller
                rev = "v1.10.1";
                hash = "sha256-blN5b1ENSwEIC+jF8nVYZu4Dyi82y1E5Z28OR4mfhKs=";
              };
              crdFiles = [ "config/crd/bases/kustomize.toolkit.fluxcd.io_kustomizations.yaml" ];
            })
            (
              { lib, ... }:
              {
                options.flux.dependsOn = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  description = ''
                    Apps whose Kustomization must be Ready before this app's is
                    applied: the ones serving a failurePolicy Fail admission
                    webhook for objects in this app, and external-secrets-config
                    (the store) for an app with ExternalSecrets. CRDs need no
                    entry: the k3s bootstrap applies every app's CRDs first.
                  '';
                };
              }
            )
          ];
          defaults.helm.transformer = map (manifest: unhook (stripHelmLabels manifest));
        };
      };
  };
in
{
  den.schema.cluster.includes = [ nixidyDefaultsAspect ];
}
