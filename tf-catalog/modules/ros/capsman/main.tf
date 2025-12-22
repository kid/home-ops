resource "routeros_wifi_channel" "capxr0" {
  name              = "capxr0"
  frequency         = ["2437", "5500-5720"]
  skip_dfs_channels = "10min-cac"
}

resource "routeros_wifi_channel" "capxr1" {
  name      = "capxr1"
  frequency = ["2462", "5180-5340"]
}

resource "routeros_wifi_security" "wpa2" {
  name                  = "wpa2"
  authentication_types  = ["wpa2-psk"]
  encryption            = ["ccmp"]
  ft                    = true
  ft_over_ds            = true
  ft_preserve_vlanid    = true
  disable_pmkid         = true
  connect_priority      = "0/1"
  management_protection = "allowed"
  passphrase            = data.sops_file.routeros_secrets.data["wifi.Wayland"]
}

resource "routeros_wifi_configuration" "capxr0-2g" {
  name                  = "capxr0-2g"
  ssid                  = "Weyland"
  country               = "Belgium"
  multicast_enhance     = "enabled"
  deprioritize_unii_3_4 = true

  channel = {
    config = "capxr0"
    width  = "20mhz"
  }

  security = {
    config = "wpa2"
  }
}
