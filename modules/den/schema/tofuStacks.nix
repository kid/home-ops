# Named tofu stacks: a den entity per stack whose resources no cluster or
# RouterOS device owns (account-wide Cloudflare records, later e.g. the GitHub
# repositories). Resolved under the fleet (modules/den/policies/fleet.nix);
# den.tofuStacks.<name>'s aspect (den.aspects.<name>) and its includes
# contribute `tofu` content, collected into tf-stacks/<name> by
# modules/den/batteries/tofu/tofu.nix.
{ lib, den, ... }:
{
  config.den.schema.tofuStack.isEntity = true;

  options.den.tofuStacks = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }:
        {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              default = name;
              description = "Stack name: its directory under tf-stacks/ and its `just tofu` key";
            };

            aspect = lib.mkOption {
              type = lib.types.raw;
              default = den.aspects.${name} or { };
              defaultText = "den.aspects.<name>";
              description = "Aspect whose `tofu` content (with its includes') makes up the stack";
            };
          };
        }
      )
    );
    default = { };
    description = "Named tofu stacks, for resources no cluster or RouterOS device owns";
  };
}
