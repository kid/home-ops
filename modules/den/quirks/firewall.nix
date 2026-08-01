# RouterOS firewall-rule fragments, contributed by any network/cluster/etc.
# aspect and collected onto every RouterOS device (modules/den/policies/pipes.nix's
# routeros-device-collect-firewall). Fragment shape: { network; input ? [ ]; forward
# ? [ ]; } — the `network` field names the den.networks entry the fragment
# targets; ros-firewall.nix (the only current consumer) groups fragments by
# that field before merging them into vlans_input_rules/vlans_forward_rules.
{
  den.quirks.firewall.description = "RouterOS forward/input firewall-rule fragments, each tagged with the den.networks name they target";
}
