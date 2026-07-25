# Nix -> HCL text renderer for a terragrunt.hcl leaf's `locals`/`inputs`
# block bodies. No nixopslab precedent (terranix renders to Terraform's JSON
# syntax, where any HCL-shaped value is just a JSON value); here we render
# actual HCL text, since tf-catalog/modules/ros/* stay real Terraform
# modules invoked via Terragrunt's `terraform.source`, not terranix.
#
# `hcl.raw text` escapes the renderer for values that must stay a live HCL
# expression rather than a value pre-computed by Nix — e.g.
# `"${get_repo_root()}/secrets/prd/routeros.sops.yaml"`, which has to
# resolve against the *checkout* Terragrunt is run from, not the Nix store
# path this flake evaluates in.
#
# Plain lib file (underscore-prefixed so import-tree skips it), imported
# directly by modules/terragrunt/render.nix (exposes it as a top-level
# `_module.args.hcl` for device modules) and modules/terragrunt/devshell.nix
# (needs it inside `perSystem`, a separate module-args namespace).
{ lib }:
let
  isBareIdent = s: builtins.match "[A-Za-z_][A-Za-z0-9_-]*" s != null;

  quoteString = s: ''"'' + (lib.replaceStrings [ "\\" "\"" "\n" ] [ "\\\\" "\\\"" "\\n" ] s) + ''"'';

  renderKey = k: if isBareIdent k then k else quoteString k;

  indentStr = depth: lib.concatStrings (lib.replicate depth "  ");

  render =
    depth: value:
    if value == null then
      "null"
    else if builtins.isBool value then
      (if value then "true" else "false")
    else if builtins.isInt value || builtins.isFloat value then
      toString value
    else if builtins.isString value then
      quoteString value
    else if builtins.isAttrs value && value ? __hclRaw then
      value.__hclRaw
    else if builtins.isList value then
      renderList depth value
    else if builtins.isAttrs value then
      renderAttrs depth value
    else
      throw "toHCL: unsupported value: ${builtins.typeOf value}";

  renderList =
    depth: items:
    if items == [ ] then
      "[]"
    else
      "[\n"
      + lib.concatMapStrings (item: indentStr (depth + 1) + render (depth + 1) item + ",\n") items
      + indentStr depth
      + "]";

  renderAttrs =
    depth: attrs:
    let
      names = builtins.attrNames attrs;
    in
    if names == [ ] then
      "{}"
    else
      "{\n"
      + lib.concatMapStrings (
        k: indentStr (depth + 1) + renderKey k + " = " + render (depth + 1) attrs.${k} + "\n"
      ) names
      + indentStr depth
      + "}";
in
{
  raw = text: { __hclRaw = text; };
  # Renders a Nix value as an HCL literal, e.g. for an `inputs = <value>`
  # block body.
  toValue = render 0;
}
