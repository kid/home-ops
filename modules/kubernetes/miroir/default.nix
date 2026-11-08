# MiroirNode isn't a core Kubernetes type, so nixidy has no built-in typed
# options for it — generators.fromChartCRDModule generates it live from
# the chart's own CRDs, installed by Helm automatically.
_: {
  # miroir-agent runs hostNetwork: true with its own port 9810.
  den.aspects.kubernetes.miroir.firewall-ports = _: [
    {
      port = 9810;
      protocol = "TCP";
      description = "miroir-agent";
      from = [
        "cluster"
        "remote-node"
      ];
    }
    # DRBD replication links: one port per replicated volume, ascending
    # from the chart's drbd.portBase (7000) with no upper bound of its own.
    {
      port = 7000;
      endPort = 7999;
      protocol = "TCP";
      description = "miroir DRBD replication";
      from = [
        "cluster"
        "remote-node"
      ];
    }
  ];

  den.aspects.kubernetes.miroir.k8s-manifests =
    {
      charts,
      generators,
      cluster,
      lib,
      miroir-nodes ? [ ],
      ...
    }:
    let
      storageAddresses = miroir-nodes |> lib.filter (n: n.address != null) |> map (n: n.address);
    in
    {
      nixidy.applicationImports = [
        (generators.fromChartCRDModule {
          name = "miroir";
          chart = charts.home-operations.miroir;
          kindFilter = [ "MiroirNode" ];
        })
        (generators.fromChartCRDModule {
          name = "snapshot-controller";
          chart = charts.home-operations.snapshot-controller;
          kindFilter = [ "VolumeSnapshotClass" ];
        })
      ];

      applications.miroir = {
        namespace = "miroir-system";

        resources.ciliumNetworkPolicies = with cluster.methods.netpol; {
          miroir-controller =
            mkPolicy
              {
                "app.kubernetes.io/name" = "miroir";
                "app.kubernetes.io/component" = "controller";
              }
              {
                ingress = [ (scrapeIngress [ 8081 ]) ];
                egress = [ apiserverEgress ];
              };
        };

        helm.releases.miroir = {
          chart = charts.home-operations.miroir;
          values = {
            monitoring = {
              podMonitor.enabled = true;
              dashboards = {
                enabled = true;
                grafanaOperator = {
                  enabled = true;
                  matchLabels.dashboards = "grafana";
                };
              };
            };
            resources.requests.memory = "64Mi";
            sidecars.resizer.resources.requests.memory = "64Mi";
            agent = {
              resources = {
                requests.memory = "64Mi";
                limits.memory = "192Mi";
              };
              registrar.resources.requests.memory = "32Mi";
            };
          };
        };

        resources.miroirNodes =
          miroir-nodes
          |> map (
            n:
            lib.nameValuePair n.hostname {
              spec = {
                pools = [
                  {
                    name = "default";
                    # The VG exists: the agent makes its thin pool there.
                    lvmthin = { };
                  }
                ];
              }
              // lib.optionalAttrs (n.address != null) { inherit (n) address; };
            }
          )
          |> lib.listToAttrs;

        # Untyped (as in cilium/host-firewall.nix), so the empty nodeSelector survives.
        yamls = lib.optionals (storageAddresses != [ ]) [
          (builtins.toJSON {
            apiVersion = "cilium.io/v2";
            kind = "CiliumClusterwideNetworkPolicy";
            metadata.name = "miroir-drbd-storage";
            spec = {
              description = "DRBD replication between the miroir nodes' Storage VLAN addresses (MiroirNode spec.address); Cilium knows only their InternalIPs, so these sources are world.";
              nodeSelector = { };
              ingress = [
                {
                  fromCIDR = map (a: "${a}/32") storageAddresses;
                  toPorts = [
                    {
                      ports = [
                        {
                          port = "7000";
                          endPort = 7999;
                          protocol = "TCP";
                        }
                      ];
                    }
                  ];
                }
              ];
            };
          })
        ];

        resources.volumeSnapshotClasses.miroir = {
          metadata.annotations."snapshot.storage.kubernetes.io/is-default-class" = "true";
          driver = "miroir.home-operations.com";
          deletionPolicy = "Delete";
        };

        resources.storageClasses.miroir = {
          metadata.annotations."storageclass.kubernetes.io/is-default-class" = "true";
          provisioner = "miroir.home-operations.com";
          volumeBindingMode = "WaitForFirstConsumer";
          allowVolumeExpansion = true;
          parameters = {
            "miroir.home-operations.com/replicas" = "1";
            "csi.storage.k8s.io/fstype" = "ext4";
          };
        };

        # A second class, not a change to the default one: StorageClass
        # parameters are immutable, and a volume cannot gain a replication
        # layer in place. Two storage nodes leave no third one for a quorum
        # tie-breaker, and miroir's default `freeze` policy would stop I/O on
        # both legs whenever either node reboots: the surviving leg keeps
        # writing instead. ReadWriteOncePod on every claim keeps a second
        # writer from starting on the other node while the old pod exists.
        resources.storageClasses.miroir-replicated = {
          provisioner = "miroir.home-operations.com";
          volumeBindingMode = "WaitForFirstConsumer";
          allowVolumeExpansion = true;
          parameters = {
            "miroir.home-operations.com/replicas" = "2";
            "miroir.home-operations.com/quorum" = "last-man-standing";
            "csi.storage.k8s.io/fstype" = "ext4";
          };
        };
      };
    };
}
