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

# DNS is external-dns-cloudflare's job (see
# tf-catalog/modules/external-dns-cloudflare and modules/den/aspects/
# kubernetes/external-dns-cloudflare) — no DNS record here.

# An exact `name` filter here ("Cloudflare Tunnel") returned an empty result
# against the real API — Cloudflare's own naming/casing for this group isn't
# documented reliably enough to hardcode. List everything instead and match
# on a case-insensitive substring, so exact spelling/casing doesn't matter.
data "cloudflare_account_api_token_permission_groups_list" "account_all" {
  account_id = var.account_id
}

locals {
  tunnel_edit_permission_group_id = [
    for pg in data.cloudflare_account_api_token_permission_groups_list.account_all.result :
    pg.id if length(regexall("(?i)tunnel", pg.name)) > 0
  ][0]
}

resource "cloudflare_account_token" "tunnel_gateway" {
  account_id = var.account_id
  name       = "cloudflare-tunnel-gateway-${var.cluster_name}"

  policies = [{
    effect = "allow"
    permission_groups = [
      { id = local.tunnel_edit_permission_group_id }
    ]
    resources = jsonencode({
      "com.cloudflare.api.account.${var.account_id}" = "*"
    })
  }]
}

# The connector token the in-cluster proxy authenticates with
# (proxy.tunnelTokenSecretRef).
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
# on its own, since it ends up published in public DNS CNAMEs anyway.
output "tunnel_id" {
  value = cloudflare_zero_trust_tunnel_cloudflared.k8s.id
}
