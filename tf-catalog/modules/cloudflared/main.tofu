terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 3.0"
    }
  }
}

variable "cluster_name" {
  type = string
}

variable "account_id" {
  type = string
}

variable "cloudflare_zone_id" {
  type = string
}

provider "onepassword" {}

data "onepassword_vault" "home_ops_prd" {
  name = "home-ops-prd"
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "k8s" {
  account_id = var.account_id
  name       = "k8s-${var.cluster_name}"
  # The lexfrei/cloudflare-tunnel-gateway-controller in-cluster controller
  # manages ingress registration itself via the Cloudflare API on every
  # Gateway API route change, not a local cloudflared config file.
  config_src = "cloudflare"
}

# Covers every current and future exposed hostname with one static record —
# see modules/den/aspects/kubernetes/cloudflared/default.nix. The controller's
# own explicit per-app HTTPRoute allow-list is the real access boundary, not
# this DNS record: an unlisted hostname still resolves but has no route.
resource "cloudflare_dns_record" "tunnel_wildcard" {
  zone_id = var.cloudflare_zone_id
  name    = "*"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.k8s.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

# TODO: confirm the exact permission group name at apply time (same caveat
# as tf-catalog/modules/cert-manager's own DNS-Write lookup).
data "cloudflare_account_api_token_permission_groups_list" "tunnel_edit" {
  account_id = var.account_id
  name       = "Cloudflare%20Tunnel"
}

resource "cloudflare_account_token" "tunnel_gateway" {
  account_id = var.account_id
  name       = "cloudflare-tunnel-gateway-${var.cluster_name}"

  policies = [{
    effect = "allow"
    permission_groups = [
      { id = data.cloudflare_account_api_token_permission_groups_list.tunnel_edit.result[0].id }
    ]
    resources = jsonencode({
      "com.cloudflare.api.account.${var.account_id}" = "*"
    })
  }]
}

# The connector token the in-cluster proxy authenticates with
# (proxy.tunnelTokenSecretRef). TODO: confirm the exact resource/data-source
# name against the pinned provider at apply time.
data "cloudflare_zero_trust_tunnel_cloudflared_token" "k8s" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.k8s.id
}

resource "onepassword_item" "cloudflared_credentials" {
  vault    = data.onepassword_vault.home_ops_prd.uuid
  title    = "cloudflared-tunnel-credentials"
  category = "secure_note"

  section {
    label = "credentials"

    field {
      label = "api-token"
      type  = "CONCEALED"
      value = cloudflare_account_token.tunnel_gateway.value
    }

    field {
      label = "tunnel-token"
      type  = "CONCEALED"
      value = data.cloudflare_zero_trust_tunnel_cloudflared_token.k8s.token
    }
  }
}

# The one value a human copies once into cluster.cloudflare.tunnelId
# (modules/den/schema/clusters.nix) after the bootstrap apply — not sensitive
# on its own, since it ends up published in the wildcard DNS CNAME anyway.
output "tunnel_id" {
  value = cloudflare_zero_trust_tunnel_cloudflared.k8s.id
}
