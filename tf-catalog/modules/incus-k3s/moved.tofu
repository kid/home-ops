# Temporary: state addresses from before incus-k3s-vlan and
# incus-vlan-networks were merged into this module. Remove after the prd
# incus stack is applied.
moved {
  from = module.network.incus_network.this
  to   = incus_network.this
}

moved {
  from = module.nodes.incus_image.base
  to   = incus_image.base
}

moved {
  from = module.nodes.incus_instance.k3s
  to   = incus_instance.k3s
}

moved {
  from = module.nodes.terraform_data.install_id
  to   = terraform_data.install_id
}

moved {
  from = module.nodes.terraform_data.prepare_install
  to   = terraform_data.prepare_install
}

moved {
  from = module.nodes.module.install
  to   = module.install
}
