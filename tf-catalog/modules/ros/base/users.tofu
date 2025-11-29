locals {
  groups    = try(yamldecode(data.sops_file.routeros_secrets.raw).groups, {})
  users     = try(yamldecode(data.sops_file.routeros_secrets.raw).users, {})
  usernames = nonsensitive(toset(keys(local.users)))
}

resource "routeros_system_user_group" "groups" {
  for_each = nonsensitive(toset(keys(local.groups)))
  name     = each.key
  policy   = nonsensitive(try(local.groups[each.key].policies, []))
}

resource "routeros_system_user" "users" {
  depends_on = [routeros_system_user_group.groups]
  for_each   = local.usernames
  name       = each.key
  password   = try(local.users[each.key].password, null)
  group      = nonsensitive(try(local.users[each.key].group, "full"))
  comment    = nonsensitive(try(local.users[each.key].comment, null))
  disabled   = nonsensitive(try(local.users[each.key].disabled, false))
}

resource "routeros_system_user_sshkeys" "users_keys" {
  for_each = nonsensitive({
    for _, v in flatten([for name, user in local.users : [
      for idx, key in try(user.ssh_keys, []) : { idx = idx, user = name, key = key }
    ]]) : "${v.user}_${v.idx}" => v
  })

  user = routeros_system_user.users[each.value.user].name
  key  = each.value.key
}

import {
  for_each = setintersection(local.usernames, ["admin"])
  to       = routeros_system_user.users[each.key]
  id       = "*1"
}
