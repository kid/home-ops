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
  depends_on             = [routeros_wifi_security_multi_passphrase.groups]
  name                   = "wpa2"
  authentication_types   = ["wpa2-psk"]
  encryption             = ["ccmp"]
  ft                     = true
  ft_over_ds             = true
  ft_preserve_vlanid     = true
  disable_pmkid          = true
  connect_priority       = "0/1"
  management_protection  = "allowed"
  multi_passphrase_group = data.sops_file.routeros_secrets.data["wifi.ssid"]
}

resource "routeros_wifi_security_multi_passphrase" "groups" {
  for_each   = var.passphrase_groups
  group      = data.sops_file.routeros_secrets.data["wifi.ssid"]
  vlan_id    = each.value.vlan_id
  isolation  = lookup(each.value, "isolated", false)
  passphrase = data.sops_file.routeros_secrets.data["wifi.passphrases.${each.key}"]
}

resource "routeros_wifi_steering" "default" {
  name = "default"
  rrm  = true
  wnm  = true
}

resource "routeros_wifi_datapath" "default" {
  name   = "default"
  bridge = var.bridge_name
}

resource "routeros_wifi_datapath" "lan" {
  name    = "lan"
  bridge  = "bridge1"
  vlan_id = 100
}

resource "routeros_wifi_configuration" "capxr0-2g" {
  name              = "capxr0-2g"
  ssid              = data.sops_file.routeros_secrets.data["wifi.ssid"]
  country           = "Belgium"
  multicast_enhance = "enabled"
  dtim_period       = 4
  tx_power          = 10

  channel = {
    config = routeros_wifi_channel.channel_6.name
  }

  datapath = {
    config = routeros_wifi_datapath.default.name
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
  ssid              = data.sops_file.routeros_secrets.data["wifi.ssid"]
  country           = "Belgium"
  multicast_enhance = "enabled"
  dtim_period       = 4
  tx_power          = 10

  channel = {
    config = routeros_wifi_channel.channel_11.name
  }

  datapath = {
    config = routeros_wifi_datapath.default.name
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
  ssid              = data.sops_file.routeros_secrets.data["wifi.ssid"]
  country           = "Belgium"
  multicast_enhance = "enabled"
  dtim_period       = 4
  tx_power          = 23

  channel = {
    config = routeros_wifi_channel.U-NII-2C.name
  }

  datapath = {
    config = routeros_wifi_datapath.default.name
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
  ssid              = data.sops_file.routeros_secrets.data["wifi.ssid"]
  country           = "Belgium"
  multicast_enhance = "enabled"
  dtim_period       = 4
  tx_power          = 23

  channel = {
    config = routeros_wifi_channel.U-NII-1.name
  }

  datapath = {
    config = routeros_wifi_datapath.default.name
  }

  security = {
    config = "wpa2"
  }

  steering = {
    config = routeros_wifi_steering.default.name
  }
}

resource "routeros_wifi_configuration" "capxr0-5g-only" {
  name              = "capxr0-5g-only"
  ssid              = "${data.sops_file.routeros_secrets.data["wifi.ssid"]}-Ghz"
  country           = "Belgium"
  multicast_enhance = "enabled"
  dtim_period       = 4
  tx_power          = 23

  channel = {
    config = routeros_wifi_channel.U-NII-2C.name
  }

  datapath = {
    config = routeros_wifi_datapath.default.name
  }

  security = {
    config = routeros_wifi_security.wpa2.name
  }

  steering = {
    config = routeros_wifi_steering.default.name
  }
}

resource "routeros_wifi_configuration" "capxr1-5g-only" {
  name              = "capxr1-5g-only"
  ssid              = "${data.sops_file.routeros_secrets.data["wifi.ssid"]}-Ghz"
  country           = "Belgium"
  multicast_enhance = "enabled"
  dtim_period       = 4
  tx_power          = 23

  channel = {
    config = routeros_wifi_channel.U-NII-1.name
  }

  datapath = {
    config = routeros_wifi_datapath.default.name
  }

  security = {
    config = routeros_wifi_security.wpa2.name
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
  slave_configurations = [routeros_wifi_configuration.capxr0-5g-only.name]
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
  slave_configurations = [routeros_wifi_configuration.capxr1-5g-only.name]
}

moved {
  from = routeros_wifi_configuration.wifi-5g-only-capxr0
  to   = routeros_wifi_configuration.capxr0-5g-only
}

moved {
  from = routeros_wifi_configuration.wifi-5g-only-capxr1
  to   = routeros_wifi_configuration.capxr1-5g-only
}
