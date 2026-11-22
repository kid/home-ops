include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules//generated-secrets"
}

inputs = {
  items = {
    alertmanager-ha-alerts-webhook = {
      field   = "webhook-id"
      length  = 32
      special = false
    }
    alertmanager-ha-watchdog-webhook = {
      field   = "webhook-id"
      length  = 32
      special = false
    }
    animarr-api-key = {
      field       = "api-key"
      length      = 32
      min_numeric = 10
      special     = false
      upper       = false
    }
    envoy-oidc-hmac = {
      field            = "hmac-secret"
      length           = 32
      min_numeric      = 8
      min_special      = 8
      override_special = "~!@#$%^&*()_+`-={}|[]\\:\"<>?,./"
    }
    mosquitto-frigate = {
      field       = "password"
      length      = 32
      min_numeric = 10
      special     = false
      upper       = false
    }
    mosquitto-home-assistant = {
      field       = "password"
      length      = 32
      min_numeric = 10
      special     = false
      upper       = false
    }
    mosquitto-zigbee2mqtt = {
      field       = "password"
      length      = 32
      min_numeric = 10
      special     = false
      upper       = false
    }
    prowlarr-api-key = {
      field       = "api-key"
      length      = 32
      min_numeric = 10
      special     = false
      upper       = false
    }
    radarr-api-key = {
      field       = "api-key"
      length      = 32
      min_numeric = 10
      special     = false
      upper       = false
    }
    sabnzbd-api-key = {
      field       = "api-key"
      length      = 32
      min_numeric = 10
      special     = false
      upper       = false
    }
    sonarr-api-key = {
      field       = "api-key"
      length      = 32
      min_numeric = 10
      special     = false
      upper       = false
    }
  }
  vault = "home-ops-prd"
}
