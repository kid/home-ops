{ config, ... }:
let
  routerosEndpoint = config.den.routerosDevices.rb5009.routerosEndpoint;
in
{
  den.aspects.external-dns.k8s-manifests =
    { charts, cluster, ... }:
    let
      mikrotikCredentials = cluster.methods.mkSopsSecret {
        namespace = "external-dns";
        name = "mikrotik-credentials";
      };
    in
    {
      applications.external-dns = {
        namespace = "external-dns";
        createNamespace = true;

        helm.releases.external-dns = {
          chart = charts.kubernetes-sigs.external-dns;
          values = {
            fullnameOverride = "external-dns-mikrotik";
            replicaCount = 1;
            sources = [
              "gateway-httproute"
              "service"
              "crd"
            ];
            registry = "txt";
            txtOwnerId = "prd";
            txtPrefix = "k8s.";
            domainFilters = [ cluster.domain ];
            policy = "sync";

            provider = {
              name = "webhook";
              webhook = {
                image = {
                  repository = "ghcr.io/mirceanton/external-dns-provider-mikrotik";
                  # renovate: datasource=docker depName=ghcr.io/mirceanton/external-dns-provider-mikrotik
                  tag = "v1.6.3@sha256:5794c1572153346e030a7de898e58c1fb81e6bd2f3eea563aabfa6d64ed199e0";
                  pullPolicy = "IfNotPresent";
                };
                env = [
                  {
                    name = "MIKROTIK_DEFAULT_TTL";
                    value = "1800";
                  }
                  {
                    name = "MIKROTIK_DEFAULT_COMMENT";
                    value = "Managed by ExternalDNS";
                  }
                  {
                    name = "MIKROTIK_BASEURL";
                    value = "https://${routerosEndpoint}:443";
                  }
                  {
                    name = "MIKROTIK_USERNAME";
                    value = "external-dns";
                  }
                  {
                    name = "MIKROTIK_PASSWORD";
                    valueFrom.secretKeyRef = {
                      name = "mikrotik-credentials";
                      key = "MIKROTIK_PASSWORD";
                    };
                  }
                  {
                    name = "MIKROTIK_SKIP_TLS_VERIFY";
                    value = "true";
                  }
                ];
                livenessProbe = {
                  httpGet = {
                    path = "/healthz";
                    port = "http-webhook";
                  };
                  initialDelaySeconds = 10;
                  timeoutSeconds = 5;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/readyz";
                    port = "http-webhook";
                  };
                  initialDelaySeconds = 10;
                  timeoutSeconds = 5;
                };
              };
            };

            extraArgs = [
              "--managed-record-types=A"
              "--managed-record-types=CNAME"
              "--managed-record-types=TXT"
            ];
          };
        };

        yamls = [ mikrotikCredentials ];
      };
    };
}
