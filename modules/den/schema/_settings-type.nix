# The type of `host.settings`, generated from every aspect's `settings`
# block (den's Aspect Settings guide): `den.aspects.disk.zfs.settings.device`
# becomes `host.settings.disk.zfs.device`. Imported by ./settings.nix; the
# leading underscore keeps import-tree from loading it as a module.
{ den, lib }:
let
  inherit (lib) mkOption types;
  inherit (den.lib.aspects.fx.keyClassification) isStructuralKey;

  # Pipeline machinery, class content or quirk data: never child aspects.
  skipKey = k: isStructuralKey k || (den.classes or { }) ? ${k} || (den.quirks or { }) ? ${k};

  # A bare attrset of options, or a module with options/config/imports.
  reshape = raw: if raw ? options || raw ? config || raw ? imports then raw else { options = raw; };

  hasSettingsDeep =
    node:
    builtins.isAttrs node
    && (
      node ? settings
      || lib.any (k: !(skipKey k) && hasSettingsDeep (node.${k} or null)) (builtins.attrNames node)
    );

  # One submodule per aspect-tree node: its own settings, plus one option per
  # child aspect that has settings somewhere below it.
  nodeModule =
    node:
    let
      own = reshape (node.settings or { });
      children = lib.filterAttrs (k: v: !(skipKey k) && builtins.isAttrs v && hasSettingsDeep v) node;
    in
    {
      imports = own.imports or [ ];
      config = own.config or { };
      options =
        (own.options or { })
        // lib.mapAttrs (
          name: child:
          mkOption {
            type = types.submodule (nodeModule child);
            default = { };
            description = "Settings under ${name}";
          }
        ) children;
    };
in
types.submodule (nodeModule (den.aspects or { }))
