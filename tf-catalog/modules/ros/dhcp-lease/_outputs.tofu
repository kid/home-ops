output "lease_id" {
  description = "DHCP lease ID"
  value       = routeros_ip_dhcp_server_lease.self.id
}

output "dns_record_ids" {
  description = "Map of DNS record IDs keyed by index"
  value       = { for idx, record in routeros_ip_dns_record.lease_a : idx => record.id }
}
