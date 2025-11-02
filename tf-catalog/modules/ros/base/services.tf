locals {
  enabled_services = ["www-ssl", "ssh", "winbox"]
  ssl_services     = ["www-ssl"]
}

data "routeros_ip_services" "all" {
  filter = {
    dynamic = false
  }
}

resource "routeros_ip_service" "all" {
  for_each    = { for svc in data.routeros_ip_services.all.services : svc.name => svc }
  numbers     = each.key
  port        = each.value.port
  disabled    = !contains(local.enabled_services, each.key)
  tls_version = contains(local.ssl_services, each.key) ? "only-1.2" : null
  certificate = contains(local.ssl_services, each.key) ? routeros_system_certificate.webfig.name : null
}

resource "routeros_ip_ssh_server" "self" {
  strong_crypto = true
  # always_allow_password_login = false
  host_key_type = "ed25519"
}
