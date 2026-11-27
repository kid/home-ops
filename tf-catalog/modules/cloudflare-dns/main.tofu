# Plain Cloudflare DNS records for account-wide names no app or cluster owns.
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

variable "zone_id" {
  type = string
}

variable "records" {
  type = map(object({
    type    = string
    content = string
    proxied = optional(bool, false)
    ttl     = optional(number, 300)
    comment = optional(string)
  }))
  description = "DNS records keyed by fully qualified name"
}

resource "cloudflare_dns_record" "this" {
  for_each = var.records
  zone_id  = var.zone_id
  name     = each.key
  type     = each.value.type
  content  = each.value.content
  proxied  = each.value.proxied
  ttl      = each.value.ttl
  comment  = each.value.comment
}
