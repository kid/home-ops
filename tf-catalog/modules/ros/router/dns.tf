resource "routeros_ip_dns" "server" {
  allow_remote_requests = true
  servers               = var.dns_upstream_servers
  cache_size            = 8192
  cache_max_ttl         = "1d"
}

resource "routeros_ip_dns_record" "static" {
  for_each = var.dns_static_records
  name     = each.key
  address  = each.value.address
  comment  = each.value.comment
  type     = each.value.type
}
