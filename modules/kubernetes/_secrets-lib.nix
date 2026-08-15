# Shared per-app secret-declaration convention: one spec drives both the
# 1Password item Terraform creates (modules/flake/onepassword-items.nix,
# tf-modules/onepassword-items/) and the ExternalSecret k8s manifest that
# reads it (modules/kubernetes/external-secrets/default.nix), so the two can
# never drift out of sync with each other. Leading underscore: import-tree
# skips this, same convention as modules/network/_ros-lib.nix. Needs no
# outside args, so unlike that file this is a plain attrset, not a function.
{
  # spec = { title, vault ? "home-ops", category, fields }
  # field = { name, generate ? false, length ? 32, k8sKey ? name }
  #   generate = true  -> Terraform mints the value itself (random password/
  #                        token), fully automated.
  #   generate = false -> Terraform creates the field empty; a human or
  #                        secretspec fills the real value in afterward.

  mkOnePasswordItem =
    {
      title,
      vault ? "home-ops",
      category,
      fields,
    }:
    {
      inherit title vault category;
      fields = map (f: {
        inherit (f) name;
        generate = f.generate or false;
        length = f.length or 32;
      }) fields;
    };

  # ESO's 1Password SDK provider (onepasswordSDK) matches ExternalSecret
  # .data[] entries by a single combined "<item>/[section/]<field>"
  # remoteRef.key — unlike the older Connect provider, there's no separate
  # `property` field (external-secrets.io/main/provider/1password-sdk).
  # tf-modules/onepassword-items/main.tf puts every custom field inside one
  # fixed "fields" section (the provider's onepassword_item resource has no
  # top-level custom-field slot, only section_map/section) — this "fields"
  # literal must match that module's section_map key exactly.
  mkExternalSecretData =
    { title, fields, ... }:
    map (f: {
      secretKey = f.k8sKey or f.name;
      remoteRef.key = "${title}/fields/${f.name}";
    }) fields;
}
