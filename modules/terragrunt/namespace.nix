# Everything Terraform/Terragrunt-related in this repo — the ros-* aspects,
# the terragrunt-stacks class, and each device's own self-aspect — lives
# under den's "tf" namespace instead of the flat den.aspects/den.classes
# registries. `false` = local only, not exported via flake.denful.tf.
{ inputs, ... }:
{
  imports = [ (inputs.den.namespace "tf" false) ];
}
