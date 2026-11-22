terraform {
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 3.0"
    }
  }
}

# Frigate camera names; each camera's stream login is the reolink-<name> item
# in home-ops.
variable "cameras" {
  type = list(string)
}

provider "onepassword" {}

data "onepassword_vault" "home_ops" {
  name = "home-ops"
}

data "onepassword_vault" "home_ops_prd" {
  name = "home-ops-prd"
}

data "onepassword_item" "camera" {
  for_each = toset(var.cameras)
  vault    = data.onepassword_vault.home_ops.uuid
  title    = "reolink-${each.key}"
}

# Only the stream login (go2rtc), not the camera's admin console login.
resource "onepassword_item" "camera" {
  for_each = toset(var.cameras)
  vault    = data.onepassword_vault.home_ops_prd.uuid
  title    = "reolink-${each.key}"
  category = "secure_note"

  section {
    label = "credentials"

    field {
      label = "username"
      type  = "STRING"
      value = data.onepassword_item.camera[each.key].username
    }

    field {
      label = "password"
      type  = "CONCEALED"
      value = data.onepassword_item.camera[each.key].password
    }
  }
}
