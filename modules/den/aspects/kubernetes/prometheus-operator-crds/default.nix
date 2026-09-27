# The ServiceMonitor/PodMonitor CRDs (Prometheus Operator's, not ours — we
# run VictoriaMetrics). No controller reads them; the victoria-metrics
# aspect's vmagent has disable_prometheus_converter left at its chart
# default (false), so victoria-metrics-operator watches these CRDs and
# converts any ServiceMonitor/PodMonitor object into its own native
# VMServiceScrape/VMPodScrape. Without these CRDs installed, every app
# chart's own serviceMonitor.enabled/podMonitor.enabled toggle fails to
# apply: Kubernetes doesn't know the resource kind.
_: {
  den.aspects.kubernetes.prometheus-operator-crds.k8s-manifests =
    { charts, ... }:
    {
      applications.prometheus-operator-crds = {
        namespace = "monitoring";
        annotations."argocd.argoproj.io/sync-wave" = "-3";

        helm.releases.prometheus-operator-crds.chart = charts.prometheus-community.prometheus-operator-crds;
      };
    };
}
