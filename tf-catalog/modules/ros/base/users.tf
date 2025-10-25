resource "routeros_system_user" "users" {
  for_each = var.users
  name     = each.key
  group    = each.value.group
  password = var.passwords[each.key]
  comment  = try(each.value.comment, null)
}

resource "routeros_system_user_sshkeys" "users_keys" {
  for_each = {
    for _, v in flatten([for name, user in var.users : [
      for idx, key in user.keys : { idx = idx, user = name, key = key }
    ]]) : "${v.user}_${v.idx}" => v
  }

  user = routeros_system_user.users[each.value.user].name
  key  = each.value.key
}
