resource "routeros_system_ntp_server" "server" {
  enabled = var.ntp_server_enabled
}

resource "routeros_system_ntp_client" "client" {
  enabled = true
  mode    = "unicast"
  servers = var.ntp_servers
}
