resource "routeros_wifi_capsman" "settings" {
  enabled        = true
  interfaces     = var.capsman_interfaces
  upgrade_policy = "suggest-same-version"
}

resource "routeros_wifi_channel" "channel_6" {
  name      = "channel-6"
  width     = "20mhz"
  frequency = ["2437"]
}

resource "routeros_wifi_channel" "channel_11" {
  name      = "channel-11"
  width     = "20mhz"
  frequency = ["2462"]
}

resource "routeros_wifi_channel" "capxr0" {
  name              = "capxr0"
  width             = "20/40/80mhz"
  frequency         = ["5500-5720"]
  skip_dfs_channels = "10min-cac"
}

resource "routeros_wifi_channel" "U-NII-1" {
  name              = "U-NII-1"
  width             = "20/40/80mhz"
  frequency         = ["5180-5240"]
  skip_dfs_channels = "10min-cac"
}

resource "routeros_wifi_channel" "U-NII-2C" {
  name              = "U-NII-2C"
  width             = "20/40/80mhz"
  frequency         = ["5480-5720"]
  skip_dfs_channels = "10min-cac"
}

resource "routeros_wifi_channel" "capxr1" {
  name              = "capxr1"
  width             = "20/40/80mhz"
  frequency         = ["5180-5340"]
  skip_dfs_channels = "10min-cac"
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

resource "routeros_wifi_steering" "default" {
  name = "default"
  rrm  = true
  wnm  = true
}

resource "routeros_wifi_datapath" "default" {
  name   = "default"
  bridge = "bridge1"
}

resource "routeros_wifi_datapath" "lan" {
  name    = "lan"
  bridge  = "bridge1"
  vlan_id = 100
}

resource "routeros_wifi_configuration" "capxr0-2g" {
  name              = "capxr0-2g"
  ssid              = "Weyland"
  country           = "Belgium"
  multicast_enhance = "enabled"
  dtim_period       = 4

  channel = {
    config = routeros_wifi_channel.channel_6.name
  }

  datapath = {
    config = routeros_wifi_datapath.lan.name
  }

  security = {
    config = routeros_wifi_security.wpa2.name
  }

  steering = {
    config = routeros_wifi_steering.default.name
  }
}

resource "routeros_wifi_configuration" "capxr1-2g" {
  name              = "capxr1-2g"
  ssid              = "Weyland"
  country           = "Belgium"
  multicast_enhance = "enabled"
  dtim_period       = 4

  channel = {
    config = routeros_wifi_channel.channel_11.name
  }

  datapath = {
    config = routeros_wifi_datapath.lan.name
  }

  security = {
    config = routeros_wifi_security.wpa2.name
  }

  steering = {
    config = routeros_wifi_steering.default.name
  }
}

resource "routeros_wifi_configuration" "capxr0-5g" {
  name              = "capxr0-5g"
  ssid              = "Weyland"
  country           = "Belgium"
  multicast_enhance = "enabled"
  dtim_period       = 4
  tx_power          = 18

  channel = {
    config = routeros_wifi_channel.U-NII-2C.name
  }

  datapath = {
    config = routeros_wifi_datapath.lan.name
  }

  security = {
    config = routeros_wifi_security.wpa2.name
  }

  steering = {
    config = routeros_wifi_steering.default.name
  }
}

resource "routeros_wifi_configuration" "capxr1-5g" {
  name              = "capxr1-5g"
  ssid              = "Weyland"
  country           = "Belgium"
  multicast_enhance = "enabled"
  dtim_period       = 4
  tx_power          = 18

  channel = {
    config = routeros_wifi_channel.U-NII-1.name
  }

  datapath = {
    config = routeros_wifi_datapath.lan.name
  }

  security = {
    config = "wpa2"
  }

  steering = {
    config = routeros_wifi_steering.default.name
  }
}

resource "routeros_wifi_provisioning" "capxr0-2g" {
  identity_regexp      = "capxr0"
  name_format          = "wifi2g-%I"
  action               = "create-dynamic-enabled"
  supported_bands      = ["2ghz-ax"]
  master_configuration = routeros_wifi_configuration.capxr0-2g.name
}

resource "routeros_wifi_provisioning" "capxr0-5g" {
  identity_regexp      = "capxr0"
  name_format          = "wifi5g-%I"
  action               = "create-dynamic-enabled"
  supported_bands      = ["5ghz-ax"]
  master_configuration = routeros_wifi_configuration.capxr0-5g.name
}

resource "routeros_wifi_provisioning" "capxr1-2g" {
  identity_regexp      = "capxr1"
  name_format          = "wifi2g-%I"
  action               = "create-dynamic-enabled"
  supported_bands      = ["2ghz-ax"]
  master_configuration = routeros_wifi_configuration.capxr1-2g.name
}

resource "routeros_wifi_provisioning" "capxr1-5g" {
  identity_regexp      = "capxr1"
  name_format          = "wifi5g-%I"
  action               = "create-dynamic-enabled"
  supported_bands      = ["5ghz-ax"]
  master_configuration = routeros_wifi_configuration.capxr1-5g.name
}
