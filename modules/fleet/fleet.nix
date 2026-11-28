# The fleet entity's own aspect: what sits above every environment
# (modules/den/policies/fleet.nix). Account-wide resources are named tofu
# stacks instead (modules/fleet/stacks/).
_: {
  den.aspects.fleet = { };
}
