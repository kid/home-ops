# vim: foldmethod=marker foldmarker={{{,}}}
# WiFi (CAPsMAN v7) configuration managed by Terraform {{{
# Uses routeros_wifi_* resources for RouterOS v7 WiFi package.
# Defines channels, security, datapath, configurations and provisioning
# for centrally managed CAPs (e.g. CAP XL ac) using 80 MHz 5GHz and 20 MHz 2.4GHz.
# Enable by setting var.capsman_enabled=true and supplying SSID/passphrase.

locals {
  capsman_enabled = true
}

variable "capsman_passphrase" {
  type        = string
  sensitive   = true
  description = "WPA2/WPA3 passphrase for CAPsMAN SSID"
  default     = "changeme"
}

variable "capsman_ssid" {
  type        = string
  description = "SSID for CAPsMAN managed access points"
  default     = "MyCapsmanWiFi"
}

variable "capsman_country" {
  type        = string
  description = "Country for CAPsMAN wireless regulations"
  default     = "Belgium"
}

# Channels {{{
# 2.4 GHz non-overlapping channels (20 MHz)
resource "routeros_wifi_channel" "ch_24" {
  name      = "2ghz-1-6-11"
  frequency = [2412, 2437, 2462]
  # extension_channel = "disabled" # 20 MHz only
}

# 5 GHz UNII-1 (non-DFS) 80 MHz block (Belgium ETSI)
resource "routeros_wifi_channel" "ch_5g_unii1" {
  name      = "5ghz-unii1-80mhz"
  frequency = [5180, 5200, 5220, 5240]
  width     = "20/40/80mhz"
}

# 5 GHz UNII-2C (DFS) 80 MHz block (fallback / second AP)
resource "routeros_wifi_channel" "ch_5g_unii2c" {
  name      = "5ghz-unii2c-80mhz"
  frequency = [5500, 5520, 5540, 5560]
  width     = "20/40/80mhz"
  # dfs_mode  = "radar-detect" # ensure CAC/DFS compliance
}
# }}}

# Security profile {{{
resource "routeros_wifi_security" "psk" {
  name                 = "home-psk"
  authentication_types = ["wpa2-psk", "wpa3-psk"]
  # encryption           = ["aes-ccm"]
  passphrase = var.capsman_passphrase
}
# }}}

# Datapath (bridge) {{{
resource "routeros_wifi_datapath" "bridge" {
  name   = "bridge-dp"
  bridge = var.bridge_name
  # client_to_client_forwarding = true
  # local_forwarding            = true
}
# }}}

# Configurations {{{
resource "routeros_wifi_configuration" "cfg_24" {
  name    = "wifi-2g"
  ssid    = var.capsman_ssid
  country = var.capsman_country
  channel = {
    config = routeros_wifi_channel.ch_24.name
  }
  datapath = {
    config = routeros_wifi_datapath.bridge.name
  }
  security = {
    config = routeros_wifi_security.psk.name
  }
}

resource "routeros_wifi_configuration" "cfg_5g_a" {
  name    = "wifi-5g-unii1"
  ssid    = var.capsman_ssid
  country = var.capsman_country
  channel = {
    config = routeros_wifi_channel.ch_5g_unii1.name
  }
  datapath = {
    config = routeros_wifi_datapath.bridge.name
  }
  security = {
    config = routeros_wifi_security.psk.name
  }
}

resource "routeros_wifi_configuration" "cfg_5g_b" {
  name    = "wifi-5g-unii2c"
  ssid    = var.capsman_ssid
  country = var.capsman_country
  channel = {
    config = routeros_wifi_channel.ch_5g_unii2c.name
  }
  datapath = {
    config = routeros_wifi_datapath.bridge.name
  }
  security = {
    config = routeros_wifi_security.psk.name
  }
}
# }}}

# Provisioning rules {{{
resource "routeros_wifi_provisioning" "prov_5g" {
  action = "create-dynamic-enabled"
  # supported_bands      = "5ghz-a/n/ac"
  master_configuration = routeros_wifi_configuration.cfg_5g_a.name
  slave_configurations = [routeros_wifi_configuration.cfg_5g_b.name]
}

resource "routeros_wifi_provisioning" "prov_24" {
  action = "create-dynamic-enabled"
  # supported_bands      = "2ghz-b/g/n"
  master_configuration = routeros_wifi_configuration.cfg_24.name
}
# }}}

# WiFi CAP settings (on controller) {{{
resource "routeros_wifi_cap" "cap" {
  enabled              = true
  discovery_interfaces = [var.bridge_name]
  caps_man_addresses   = ["127.0.0.1"]
  certificate          = "auto"
  # require_peer_certificate = false
}
# }}}
