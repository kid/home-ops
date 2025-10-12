resource "routeros_system_certificate" "local-root-cert" {
  name        = "local-root-cert"
  common_name = "local-root-cert"
  key_size    = "prime256v1"
  key_usage   = ["key-cert-sign", "crl-sign"]
  trusted     = true

  sign {}
}

resource "routeros_system_certificate" "webfig" {
  name             = "webfig-${timestamp()}"
  common_name      = "webfig"
  subject_alt_name = join(",", concat(["DNS:${var.hostname}"], var.certificate_alt_names))
  country          = var.certificate_country
  locality         = var.certificate_locality
  organization     = var.certificate_organization
  unit             = var.certificate_unit
  days_valid       = 3650
  key_usage        = ["key-cert-sign", "crl-sign", "digital-signature", "key-agreement", "tls-server"]
  key_size         = "prime256v1"

  trusted = true

  sign {
    ca = routeros_system_certificate.local-root-cert.name
  }

  lifecycle {
    ignore_changes = [name]
  }
}
