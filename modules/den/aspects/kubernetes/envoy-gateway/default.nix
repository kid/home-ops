# Envoy Gateway (https://gateway.envoyproxy.io/): the controller (replacing
# Cilium's own, see cilium/default.nix's envoy.enabled = false) and the
# shared "apps" Gateway cluster.domain apps attach HTTPRoutes to — one
# aspect, since neither is useful without the other in this repo.
{ config, ... }:
let
  mkAppHostname = clusterName: appName: "${appName}.${config.den.clusters.${clusterName}.domain}";
in
{
  den.clusters.prd.methods.mkAppHostname = mkAppHostname "prd";

  den.aspects.kubernetes.envoy-gateway.k8s-manifests =
    {
      charts,
      generators,
      cluster,
      config,
      lib,
      ...
    }:
    let
      namespace = "envoy-gateway-system";
      # Signed by the control plane's own CA, not the cluster-ca: the xDS
      # server trusts any client certificate from the CA in ca.crt, and the
      # config it serves carries the Gateways' private keys.
      caIssuerRef = {
        name = "envoy-gateway-ca";
        kind = "Issuer";
        group = "cert-manager.io";
      };
      privateKey = {
        algorithm = "ECDSA";
        size = 256;
      };
    in
    {
      nixidy.applicationImports = [
        (generators.fromChartCRDModule {
          name = "envoy-gateway-client-traffic-policy";
          chart = charts.envoyproxy.gateway-helm;
          kindFilter = [
            "ClientTrafficPolicy"
            "SecurityPolicy"
            "HTTPRouteFilter"
          ];
        })
      ];

      applications.envoy-gateway = {
        inherit namespace;

        resources.ciliumNetworkPolicies =
          with cluster.methods.netpol;
          let
            proxy = {
              "app.kubernetes.io/name" = "envoy";
            };
          in
          {
            envoy-gateway = mkPolicy { control-plane = "envoy-gateway"; } {
              ingress = [
                (fromPods proxy [ 18000 ])
                (webhookIngress 9443)
              ];
              egress = [ apiserverEgress ];
            };
            envoy-proxy = mkPolicy proxy {
              ingress = [
                # Envoy Gateway remaps privileged listener ports to 10000 + port.
                {
                  fromEntities = [ "world" ];
                  toPorts = tcp [
                    10443
                    6443
                  ];
                }
                # In-cluster clients of an app's hostname: the Gateway already
                # takes any LAN client, and each pod still needs netpol.gatewayEgress.
                {
                  fromEntities = [ "cluster" ];
                  toPorts = tcp [ 10443 ];
                }
              ];
              egress = [ clusterEgress ];
            };
          };

        helm.releases.envoy-gateway = {
          chart = charts.envoyproxy.gateway-helm;
          values = {
            crds.enabled = true;
            # cainjector fills in the caBundle certgen used to patch in.
            topologyInjector.annotations."cert-manager.io/inject-ca-from" = "${namespace}/envoy-gateway";
            deployment.envoyGateway.resources.requests = {
              cpu = "10m";
              memory = "128Mi";
            };
          };

          # The chart can't disable certgen, which would generate the control
          # plane certs and the OIDC HMAC secret below once, at install, and
          # never renew them.
          transformer =
            manifests:
            builtins.filter (m: !lib.hasPrefix "envoy-gateway-gateway-helm-certgen" m.metadata.name) (
              config.nixidy.defaults.helm.transformer manifests
            );
        };

        # The control plane's mTLS: the controller serves xDS (and the topology
        # injector webhook) with the envoy-gateway Secret, proxies connect with
        # the envoy one, each trusting the other through its ca.crt. Both pick
        # up a renewed certificate without a restart.
        resources.issuers.envoy-gateway-selfsigned.spec.selfSigned = { };

        # Long-lived, and rotationPolicy Never keeps the key on renewal, so
        # leaves signed before it still verify.
        resources.certificates.envoy-gateway-ca.spec = {
          isCA = true;
          commonName = "envoy-gateway-ca";
          secretName = "envoy-gateway-ca";
          duration = "87600h";
          privateKey = privateKey // {
            rotationPolicy = "Never";
          };
          issuerRef = {
            name = "envoy-gateway-selfsigned";
            kind = "Issuer";
            group = "cert-manager.io";
          };
        };

        resources.issuers.envoy-gateway-ca.spec.ca.secretName = "envoy-gateway-ca";

        # Proxies verify the controller by the envoy-gateway SAN alone.
        resources.certificates.envoy-gateway.spec = {
          secretName = "envoy-gateway";
          dnsNames = [
            "envoy-gateway"
            "envoy-gateway.${namespace}"
            "envoy-gateway.${namespace}.svc"
            "envoy-gateway.${namespace}.svc.cluster.local"
          ];
          inherit privateKey;
          issuerRef = caIssuerRef;
        };

        resources.certificates.envoy.spec = {
          secretName = "envoy";
          dnsNames = [ "*.${namespace}" ];
          inherit privateKey;
          issuerRef = caIssuerRef;
        };

        # The key SecurityPolicy's OIDC filters sign their cookies with.
        # Generated once: a new one would log every user out.
        resources.passwords.envoy-oidc-hmac.spec = {
          length = 32;
          allowRepeat = true;
          noUpper = false;
          secretKeys = [ "hmac-secret" ];
        };

        resources.externalSecrets.envoy-oidc-hmac.spec = {
          refreshPolicy = "CreatedOnce";
          target.name = "envoy-oidc-hmac";
          dataFrom = [
            {
              sourceRef.generatorRef = {
                apiVersion = "generators.external-secrets.io/v1alpha1";
                kind = "Password";
                name = "envoy-oidc-hmac";
              };
            }
          ];
        };

        resources.gatewayClasses.envoy.spec.controllerName =
          "gateway.envoyproxy.io/gatewayclass-controller";

        resources.clientTrafficPolicies.apps.spec = {
          targetRefs = [
            {
              group = "gateway.networking.k8s.io";
              kind = "Gateway";
              name = "apps";
            }
          ];
          clientIPDetection.xForwardedFor.numTrustedHops = 1;
        };

        resources.gateways.apps.spec = {
          gatewayClassName = "envoy";
          listeners = [
            {
              name = "https";
              protocol = "HTTPS";
              port = 443;
              hostname = "*.${cluster.domain}";
              tls = {
                mode = "Terminate";
                certificateRefs = [
                  {
                    group = "";
                    kind = "Secret";
                    # Issued by cert-manager's own app, see cert-manager/default.nix.
                    name = "wildcard-tls";
                  }
                ];
              };
              allowedRoutes.namespaces.from = "All";
            }
          ];
        };
      };
    };
}
