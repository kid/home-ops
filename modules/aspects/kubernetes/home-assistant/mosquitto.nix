# Mosquitto, replacing HAOS's core_mosquitto add-on: the broker between
# Zigbee2MQTT and Home Assistant. TLS only, with a server certificate from the
# cluster CA (clients trust the cluster-ca ConfigMap trust-manager puts in
# every namespace), and one password per client from the generated-secrets
# stack. No persistence: Zigbee2MQTT republishes its discovery messages when
# Home Assistant comes online.
{ lib, ... }:
let
  name = "mosquitto";
  namespace = "home-assistant";
  labels."app.kubernetes.io/name" = name;
  port = 8883;
  # The image's mosquitto user.
  uid = 1883;
  # renovate: datasource=docker depName=docker.io/library/eclipse-mosquitto
  tag = "2.1.4-alpine@sha256:fa12172a051310efe5bcb7a6a11b77bd5faacb82cbacd7742aa758bf024fd8e4";
  image = "docker.io/library/eclipse-mosquitto:${tag}";
  tlsSecret = "${name}-tls";
  # Usernames; each client's password is generated once (generated-secrets)
  # into the mosquitto-<client> 1Password item and Secret, which the client
  # reads too.
  clients = [
    "home-assistant"
    "zigbee2mqtt"
    "frigate"
  ];
  passwordSecret = client: "${name}-${client}";
  # The format of the External Secrets Password generators that made them
  # first: 32 lowercase letters and digits, 10 of them digits.
  passwordSecrets = map (client: {
    item = passwordSecret client;
    field = "password";
    length = 32;
    upper = false;
    special = false;
    min_numeric = 10;
  }) clients;
  passwordFile = "/mosquitto/auth/passwords";

  securityContext = {
    allowPrivilegeEscalation = false;
    readOnlyRootFilesystem = true;
    capabilities.drop = [ "ALL" ];
  };
in
{
  den.aspects.kubernetes.home-assistant.mosquitto.generated-secrets = _: passwordSecrets;

  den.aspects.kubernetes.home-assistant.mosquitto.k8s-manifests =
    { cluster, ... }:
    {
      applications.mosquitto = {
        inherit namespace;
        flux.dependsOn = [
          # Its server certificate.
          "cert-manager"
          # The onepassword store, for the client passwords.
          "external-secrets-config"
        ];

        resources = {
          certificates.${tlsSecret}.spec = {
            secretName = tlsSecret;
            dnsNames = [
              name
              "${name}.${namespace}"
              "${name}.${namespace}.svc"
              "${name}.${namespace}.svc.cluster.local"
            ];
            privateKey = {
              algorithm = "ECDSA";
              size = 256;
            };
            issuerRef = {
              name = "cluster-ca";
              kind = "ClusterIssuer";
              group = "cert-manager.io";
            };
          };

          # Kept across rebuilds: the clients keep them in their own settings.
          externalSecrets =
            passwordSecrets
            |> map (s: lib.nameValuePair s.item { spec = cluster.methods.mkGeneratedSecret s; })
            |> lib.listToAttrs;

          configMaps.${name}.data."mosquitto.conf" = ''
            allow_anonymous false
            password_file ${passwordFile}
            persistence false
            log_dest stdout

            listener ${toString port}
            certfile /mosquitto/tls/tls.crt
            keyfile /mosquitto/tls/tls.key
          '';

          ciliumNetworkPolicies.${name} =
            with cluster.methods.netpol;
            mkPolicy labels {
              ingress = map (client: fromPods { "app.kubernetes.io/name" = client; } [ port ]) clients;
            };

          deployments.${name}.spec = {
            strategy.type = "Recreate";
            selector.matchLabels = labels;
            template = {
              metadata = { inherit labels; };
              spec = {
                automountServiceAccountToken = false;
                # The reloader signals the broker.
                shareProcessNamespace = true;
                securityContext = {
                  runAsNonRoot = true;
                  runAsUser = uid;
                  runAsGroup = uid;
                  fsGroup = uid;
                  seccompProfile.type = "RuntimeDefault";
                };
                # Mosquitto only reads hashed passwords.
                initContainers.passwords = {
                  inherit image securityContext;
                  command = [
                    "sh"
                    "-euc"
                    ''
                      umask 077
                      : > ${passwordFile}
                      for client in ${lib.concatStringsSep " " clients}; do
                        mosquitto_passwd -b ${passwordFile} "$client" "$(cat /mosquitto/clients/$client/password)"
                      done
                    ''
                  ];
                  volumeMounts = {
                    "/mosquitto/auth".name = "auth";
                    # mosquitto_passwd writes through a temporary file.
                    "/tmp".name = "tmp";
                  }
                  // lib.genAttrs' clients (
                    client: lib.nameValuePair "/mosquitto/clients/${client}" { name = passwordSecret client; }
                  );
                };
                containers = {
                  ${name} = {
                    inherit image securityContext;
                    ports.mqtts.containerPort = port;
                    # No TCP probes: each one is a connection that never starts
                    # TLS, which Mosquitto logs as an error. A crash exits the
                    # container anyway.
                    resources = {
                      requests = {
                        # Also its CPU share when the node is contended.
                        cpu = "100m";
                        memory = "16Mi";
                      };
                      limits.memory = "128Mi";
                    };
                    volumeMounts = {
                      "/mosquitto/config".name = "config";
                      "/mosquitto/tls".name = "tls";
                      "/mosquitto/auth".name = "auth";
                    };
                  };
                  # cert-manager renews the certificate in place; Mosquitto
                  # reloads it on SIGHUP.
                  reloader = {
                    inherit image securityContext;
                    command = [
                      "sh"
                      "-c"
                      # busybox's pkill -x matches nothing here.
                      "while sleep 86400; do kill -HUP $(pidof mosquitto); done"
                    ];
                    resources = {
                      requests = {
                        cpu = "1m";
                        memory = "4Mi";
                      };
                      limits.memory = "16Mi";
                    };
                  };
                };
                volumes = {
                  config.configMap.name = name;
                  tls.secret.secretName = tlsSecret;
                  auth.emptyDir = { };
                  tmp.emptyDir = { };
                }
                // lib.genAttrs (map passwordSecret clients) (secret: {
                  secret.secretName = secret;
                });
              };
            };
          };

          services.${name}.spec = {
            selector = labels;
            ports.mqtts = {
              inherit port;
              targetPort = "mqtts";
            };
          };
        };
      };
    };
}
