# OTel Collector DaemonSet: tails every pod's log, maps it to OTel semantic
# conventions, ships OTLP to VLSingle. Replaced VLAgent, whose field names are fixed.
{ lib, ... }:
let
  # OTTL, run in order on every record. log.cache is per-record scratch state.
  transformStatements =
    let
      forKeys = keys: f: lib.concatMap f keys;
      messageKeys = [
        "msg"
        "message"
        "@m"
        "@mt"
      ];
      severities = [
        {
          regex = "^trace";
          number = "TRACE";
        }
        {
          regex = "^(debug|dbg|verbose)";
          number = "DEBUG";
        }
        {
          regex = "^(info|notice)";
          number = "INFO";
        }
        {
          regex = "^warn";
          number = "WARN";
        }
        {
          regex = "^(err|eror)";
          number = "ERROR";
        }
        {
          regex = "^(fatal|crit|panic|dpanic|alert|emerg)";
          number = "FATAL";
        }
      ];
    in
    # JSON body → attributes.
    [
      ''set(log.cache["json"], true) where IsString(log.body) and IsMatch(log.body, "^\\s*\\{")''
      ''merge_maps(log.attributes, ParseJSON(log.body), "upsert") where log.cache["json"] == true''
    ]
    # Message → body.
    ++ forKeys messageKeys (k: [
      ''set(log.body, log.attributes["${k}"]) where log.cache["msg_key"] == nil and log.attributes["${k}"] != nil''
      ''set(log.cache["msg_key"], "${k}") where log.cache["msg_key"] == nil and log.attributes["${k}"] != nil''
    ])
    # Rust tracing (kaniop, kopiur) nests the message under fields.
    ++ [
      ''set(log.body, log.attributes["fields"]["message"]) where log.cache["msg_key"] == nil and IsMap(log.attributes["fields"]) and log.attributes["fields"]["message"] != nil''
      ''set(log.cache["msg_key"], "fields.message") where log.cache["msg_key"] == nil and IsMap(log.attributes["fields"]) and log.attributes["fields"]["message"] != nil''
      ''delete_key(log.attributes["fields"], "message") where log.cache["msg_key"] == "fields.message"''
      ''merge_maps(log.attributes, log.attributes["fields"], "insert") where IsMap(log.attributes["fields"])''
      ''delete_key(log.attributes, "fields") where IsMap(log.attributes["fields"])''
    ]
    ++ forKeys [ "msg" "message" "@m" ] (k: [
      ''delete_key(log.attributes, "${k}") where log.cache["msg_key"] == "${k}"''
    ])
    ++ [
      ''delete_key(log.attributes, "@mt")''

      # klog text (kube-state-metrics, …).
      ''merge_maps(log.cache, ExtractPatterns(log.body, "^(?P<klog_sev>[IWEF])\\d{4} [0-9:.]+ +\\d+ (?P<klog_file>[^ \\]]+):(?P<klog_line>\\d+)\\] (?P<klog_msg>[\\s\\S]*)$"), "upsert") where log.cache["json"] == nil and IsString(log.body)''
      ''set(log.body, log.cache["klog_msg"]) where log.cache["klog_msg"] != nil''
      ''set(log.attributes["code.file.path"], log.cache["klog_file"]) where log.cache["klog_file"] != nil''
      ''set(log.attributes["code.line.number"], Int(log.cache["klog_line"])) where log.cache["klog_line"] != nil''
      ''set(log.cache["lvl"], "info") where log.cache["klog_sev"] == "I"''
      ''set(log.cache["lvl"], "warn") where log.cache["klog_sev"] == "W"''
      ''set(log.cache["lvl"], "error") where log.cache["klog_sev"] == "E"''
      ''set(log.cache["lvl"], "fatal") where log.cache["klog_sev"] == "F"''

      # Recyclarr's "[INF] <instance>: <message>" (Serilog's short levels):
      # v8 has no JSON output.
      ''merge_maps(log.cache, ExtractPatterns(log.body, "^\\[(?P<serilog_sev>VRB|DBG|INF|WRN|ERR|FTL)\\] (?P<serilog_msg>[\\s\\S]*)$"), "upsert") where resource.attributes["k8s.container.name"] == "recyclarr" and IsString(log.body)''
      ''set(log.body, log.cache["serilog_msg"]) where log.cache["serilog_msg"] != nil''
    ]
    ++
      lib.mapAttrsToList
        (sev: lvl: ''set(log.cache["lvl"], "${lvl}") where log.cache["serilog_sev"] == "${sev}"'')
        {
          VRB = "trace";
          DBG = "debug";
          INF = "info";
          WRN = "warn";
          ERR = "error";
          FTL = "fatal";
        }
    ++ [

      # Level → cache["lvl"], lower case. klog JSON has none: derived from v/err.
      ''set(log.cache["lvl"], ToLowerCase(log.attributes["level"])) where log.cache["lvl"] == nil and IsString(log.attributes["level"])''
      ''delete_key(log.attributes, "level") where IsString(log.attributes["level"])''
      ''set(log.cache["lvl"], ToLowerCase(log.attributes["@l"])) where log.cache["lvl"] == nil and IsString(log.attributes["@l"])''
      ''delete_key(log.attributes, "@l")''
      ''set(log.cache["lvl"], "info") where log.cache["lvl"] == nil and log.attributes["@t"] != nil''
      ''set(log.cache["lvl"], "error") where log.cache["lvl"] == nil and log.cache["json"] == true and log.attributes["err"] != nil and log.attributes["v"] == nil''
      ''set(log.cache["lvl"], "info") where log.cache["lvl"] == nil and log.cache["json"] == true and log.attributes["v"] != nil''
    ]
    # Severity; anything unmapped keeps its own spelling.
    ++ forKeys severities (s: [
      ''set(log.severity_number, SEVERITY_NUMBER_${s.number}) where IsMatch(log.cache["lvl"], "${s.regex}")''
      ''set(log.severity_text, "${s.number}") where IsMatch(log.cache["lvl"], "${s.regex}")''
    ])
    ++ [
      ''set(log.severity_text, ToUpperCase(log.cache["lvl"])) where log.cache["lvl"] != nil and log.severity_number == SEVERITY_NUMBER_UNSPECIFIED''
    ]
    # App timestamps: the CRI timestamp is the record time.
    ++ forKeys [ "time" "ts" "timestamp" "@t" ] (k: [
      ''delete_key(log.attributes, "${k}") where log.cache["json"] == true''
    ])
    ++ [
      ''delete_key(log.attributes, "t") where log.cache["json"] == true and resource.attributes["k8s.container.name"] == "grafana"''
    ]
    # Code location → code.*, from "path:line" strings.
    ++ forKeys [ "caller" "source" ] (k: [
      ''merge_maps(log.cache, ExtractPatterns(log.attributes["${k}"], "^(?P<${k}_file>.+):(?P<${k}_line>\\d+)$"), "upsert") where IsString(log.attributes["${k}"])''
      ''set(log.attributes["code.file.path"], log.cache["${k}_file"]) where log.cache["${k}_file"] != nil''
      ''set(log.attributes["code.line.number"], Int(log.cache["${k}_line"])) where log.cache["${k}_line"] != nil''
      ''delete_key(log.attributes, "${k}") where log.cache["${k}_file"] != nil''
    ])
    ++ [
      # slog's map form of source.
      ''set(log.attributes["code.function.name"], log.attributes["source"]["function"]) where IsMap(log.attributes["source"])''
      ''set(log.attributes["code.file.path"], log.attributes["source"]["file"]) where IsMap(log.attributes["source"])''
      ''set(log.attributes["code.line.number"], log.attributes["source"]["line"]) where IsMap(log.attributes["source"])''
      ''delete_key(log.attributes, "source") where IsMap(log.attributes["source"])''
      # Rust tracing.
      ''set(log.attributes["code.file.path"], log.attributes["filename"]) where log.attributes["filename"] != nil''
      ''delete_key(log.attributes, "filename")''
      ''set(log.attributes["code.line.number"], log.attributes["line_number"]) where log.attributes["line_number"] != nil''
      ''delete_key(log.attributes, "line_number")''
      # Envoy process logs emit the line as a string.
      ''set(log.attributes["code.line.number"], Int(log.attributes["code.line.number"])) where IsString(log.attributes["code.line.number"])''
    ]
    # Errors → exception.*
    ++ forKeys [ "error" "err" ] (k: [
      ''set(log.attributes["exception.message"], log.attributes["${k}"]) where log.attributes["exception.message"] == nil and IsString(log.attributes["${k}"])''
      ''delete_key(log.attributes, "${k}") where IsString(log.attributes["${k}"])''
    ])
    ++ forKeys [ "stacktrace" "stack" "@x" ] (k: [
      ''set(log.attributes["exception.stacktrace"], log.attributes["${k}"]) where log.attributes["exception.stacktrace"] == nil and IsString(log.attributes["${k}"])''
      ''delete_key(log.attributes, "${k}") where IsString(log.attributes["${k}"])''
    ])
    # Logger name → logger.name: no semconv attribute exists, and the OTel
    # scope can't be set per record.
    ++ forKeys [ "logger" "target" "subsys" ] (k: [
      ''set(log.attributes["logger.name"], log.attributes["${k}"]) where log.attributes["logger.name"] == nil and IsString(log.attributes["${k}"])''
      ''delete_key(log.attributes, "${k}") where IsString(log.attributes["${k}"])''
    ])
    ++ [
      # zigbee2mqtt's "<namespace>: <message>".
      ''merge_maps(log.cache, ExtractPatterns(log.body, "^(?P<z2m_ns>[A-Za-z0-9:_-]+): (?P<z2m_msg>[\\s\\S]*)$"), "upsert") where resource.attributes["k8s.container.name"] == "zigbee2mqtt" and IsString(log.body)''
      ''set(log.attributes["logger.name"], log.cache["z2m_ns"]) where log.cache["z2m_ns"] != nil''
      ''set(log.body, log.cache["z2m_msg"]) where log.cache["z2m_msg"] != nil''

      # CRI noise; log.iostream is semconv and stays.
      ''delete_key(log.attributes, "logtag")''
      ''delete_key(log.attributes, "log.file.path")''
    ];
in
{
  den.aspects.kubernetes.opentelemetry-collector.k8s-manifests =
    { charts, cluster, ... }:
    {
      # The agent reads the node's pod logs through hostPath volumes.
      podSecurity.namespaces.monitoring = "privileged";

      applications.opentelemetry-collector = {
        namespace = "monitoring";

        # vlsingle is reached through victoria-metrics' monitoring-internal policy.
        resources.ciliumNetworkPolicies = with cluster.methods.netpol; {
          # k8s_attributes watches pods.
          opentelemetry-collector = mkPolicy { "app.kubernetes.io/name" = "opentelemetry-collector"; } {
            egress = [ apiserverEgress ];
          };
        };

        helm.releases.opentelemetry-collector = {
          chart = charts.open-telemetry.opentelemetry-collector;
          values = {
            fullnameOverride = "opentelemetry-collector";
            mode = "daemonset";
            image.repository = "otel/opentelemetry-collector-k8s";

            # Checkpoints and the export queue live in the hostPath
            # /var/lib/otelcol. Runs as root, to read /var/log/pods.
            presets.logsCollection = {
              enabled = true;
              storeCheckpoints = true;
              includeCollectorLogs = true;
            };
            presets.kubernetesAttributes.enabled = true;

            # The defaults are hostPorts.
            ports = {
              otlp.enabled = false;
              otlp-http.enabled = false;
              jaeger-compact.enabled = false;
              jaeger-thrift.enabled = false;
              jaeger-grpc.enabled = false;
              zipkin.enabled = false;
            };

            # GOMEMLIMIT and memory_limiter key off the memory limit.
            resources = {
              requests = {
                cpu = "20m";
                memory = "96Mi";
              };
              limits.memory = "192Mi";
            };

            config = {
              receivers = {
                otlp = null;
                jaeger = null;
                zipkin = null;
                prometheus = null;
              };
              exporters.debug = null;

              # Replaces the preset's list; it still sets filter, pod_association
              # and otel_annotations.
              processors.k8s_attributes = {
                wait_for_metadata = true;
                extract.metadata = [
                  "k8s.namespace.name"
                  "k8s.pod.name"
                  "k8s.pod.uid"
                  "k8s.node.name"
                  "k8s.deployment.name"
                  "k8s.statefulset.name"
                  "k8s.daemonset.name"
                  "k8s.cronjob.name"
                  "k8s.job.name"
                  "k8s.container.name"
                  "container.image.name"
                  "container.image.tags"
                  "service.name"
                  "service.namespace"
                  "service.version"
                  "service.instance.id"
                ];
                # For transform/resource below.
                extract.labels = [
                  {
                    tag_name = "app.kubernetes.io/managed-by";
                    key = "app.kubernetes.io/managed-by";
                    from = "pod";
                  }
                ];
              };
              processors."resource/cluster".attributes = [
                {
                  key = "k8s.cluster.name";
                  value = cluster.name;
                  action = "insert";
                }
              ];
              # kopiur's Job pods would otherwise take the Job's name, a new
              # timestamp or UUID every run, as service.name.
              processors."transform/resource" = {
                error_mode = "ignore";
                log_statements = [
                  {
                    context = "resource";
                    statements = [
                      ''set(resource.attributes["service.name"], "kopiur-mover") where resource.attributes["app.kubernetes.io/managed-by"] == "kopiur"''
                      ''delete_key(resource.attributes, "app.kubernetes.io/managed-by")''
                    ];
                  }
                ];
              };
              processors."transform/logs" = {
                error_mode = "ignore";
                log_statements = transformStatements;
              };

              exporters."otlphttp/victorialogs" = {
                logs_endpoint = "http://vlsingle-victoria-metrics.monitoring.svc.cluster.local.:9428/insert/opentelemetry/v1/logs";
                # service.name is a function of the pod: no extra streams.
                headers."VL-Stream-Fields" = "k8s.namespace.name,service.name,k8s.pod.name,k8s.container.name";
                # The preset's extension: queued logs survive a VLSingle restart.
                sending_queue.storage = "file_storage";
              };

              service.pipelines = {
                metrics = null;
                traces = null;
                # The preset appends file_log. Listing k8s_attributes keeps
                # it from prepending one ahead of memory_limiter.
                logs = {
                  receivers = [ ];
                  processors = [
                    "memory_limiter"
                    "k8s_attributes"
                    "resource/cluster"
                    "transform/resource"
                    "transform/logs"
                    "batch"
                  ];
                  exporters = [ "otlphttp/victorialogs" ];
                };
              };
              service.telemetry.logs.encoding = "json";
            };
          };
        };
      };
    };
}
