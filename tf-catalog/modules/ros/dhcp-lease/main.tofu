locals {
  dns_records = [
    for record in var.records : merge(record, {
      fqdn = var.dns_zone == null ? record.name : (endswith(record.name, ".${var.dns_zone}") ? record.name : "${record.name}.${var.dns_zone}")
    })
  ]
}

resource "routeros_ip_dhcp_server_lease" "self" {
  server      = var.dhcp_server
  address     = var.lease.address
  mac_address = var.lease.mac
  comment     = var.lease.comment
  disabled    = var.lease.disabled
}

resource "routeros_ip_dns_record" "lease_a" {
  for_each = { for idx, record in local.dns_records : idx => record }

  name     = each.value.fqdn
  address  = each.value.address
  type     = each.value.type
  comment  = each.value.comment
  disabled = each.value.disabled
}
