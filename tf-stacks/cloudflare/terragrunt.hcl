include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/tf-catalog/modules//cloudflare-dns"
}

inputs = {
  records = {
    "home.kidibox.net" = {
      comment = "rb5009 public address (MikroTik IP Cloud)"
      content = "hcy083ckp76.sn.mynetname.net"
      type    = "CNAME"
    }
    "vpn.home.kidibox.net" = {
      comment = "WireGuard endpoint on rb5009"
      content = "home.kidibox.net"
      type    = "CNAME"
    }
  }
  zone_id = "dba2b63221015f1957d718defbf6b871"
}
