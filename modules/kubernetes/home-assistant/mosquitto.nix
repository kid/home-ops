# Mosquitto, replacing HAOS's core_mosquitto add-on: the broker between
# Zigbee2MQTT and Home Assistant. TLS only, with a server certificate from the
# cluster CA (clients trust the cluster-ca ConfigMap trust-manager puts in
# every namespace), and one generated password per client. No persistence:
# Zigbee2MQTT republishes its discovery messages when Home Assistant comes
# online.
{ lib, ... }:
let
  name = "mosquitto";
  namespace = "home-assistant";
  labels."app.kubernetes.io/name" = name;
  port = 8883;
  # The image's mosquitto user.
  uid = 1883;
  # renovate: datasource=docker depName=docker.io/library/eclipse-mosquitto
  tag = "2.1.2-alpine@sha256:75d6662dee52c947dc9dd9c29f1d8d7ffef78ddaf38001caa09755681e8bbc98";
  image = "docker.io/library/eclipse-mosquitto:${tag}";
  tlsSecret = "${name}-tls";
  # Usernames; each client's password is generated once into the
  # mosquitto-<client> Secret, which the client reads too.
  clients = [
    "home-assistant"
    "zigbee2mqtt"
    "frigate"
  ];
  passwordSecret = client: "${name}-${client}";
  passwordFile = "/mosquitto/auth/passwords";

  securityContext = {
    allowPrivilegeEscalation = false;
    readOnlyRootFilesystem = true;
    capabilities.drop = [ "ALL" ];
  };
in
{
  den.aspects.kubernetes.home-assistant.mosquitto.k8s-manifests =
    { cluster, ... }:
    {
      applications.mosquitto = {
        inherit namespace;
        flux.dependsOn = [
          # Its server certificate.
          "cert-manager"
          # The client passwords' Password generators and ExternalSecrets.
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

          # Generated once: the clients keep it in their own settings.
          passwords = lib.genAttrs (map passwordSecret clients) (_: {
            spec = {
              length = 32;
              digits = 10;
              symbols = 0;
              noUpper = true;
              allowRepeat = true;
              secretKeys = [ "password" ];
            };
          });
          externalSecrets = lib.genAttrs (map passwordSecret clients) (secret: {
            spec = {
              refreshPolicy = "CreatedOnce";
              target.name = secret;
              dataFrom = [
                {
                  sourceRef.generatorRef = {
                    apiVersion = "generators.external-secrets.io/v1alpha1";
                    kind = "Password";
                    name = secret;
                  };
                }
              ];
            };
          });

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
                        cpu = "10m";
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
