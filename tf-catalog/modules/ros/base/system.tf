resource "routeros_system_identity" "identity" {
  name = var.hostname
}

resource "routeros_system_clock" "timezone" {
  time_zone_name       = var.timezone
  time_zone_autodetect = false
}
