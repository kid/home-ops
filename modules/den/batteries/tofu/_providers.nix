# OpenTofu providers of the cluster tofu stacks, fetched from the OpenTofu
# registry by tofunix. `hash` covers the registry's download metadata for the
# version, so `nix run .#rehash-changed-pins` refreshes it after a Renovate
# bump. Every provider is imported into every stack (tofunix generates its
# typed options from each one's schema), so they all land in the stack's
# required_providers.
{
  cloudflare = {
    owner = "cloudflare";
    repo = "cloudflare";
    # renovate: datasource=terraform-provider depName=cloudflare/cloudflare
    version = "5.29.0";
    hash = "sha256-8HVnJ+r105auPyrw/N03vkvnL+vU1P/Rz3wR+UMBCek=";
  };
  onepassword = {
    owner = "1Password";
    repo = "onepassword";
    # renovate: datasource=terraform-provider depName=1Password/onepassword
    version = "3.4.1";
    hash = "sha256-XveWsdqRPwpKIVy+WTDDnEzRXYgMFlXaBPSFL/Lxlm4=";
    # A cgo binary, linked against /lib64/ld-linux-x86-64.so.2.
    patchElf = true;
  };
  random = {
    owner = "hashicorp";
    repo = "random";
    # renovate: datasource=terraform-provider depName=hashicorp/random
    version = "3.9.1";
    hash = "sha256-RwRhybe8XwBqrVsr+kHtTq/OszZe/v4JfmBKSkk7psU=";
  };
  github = {
    owner = "integrations";
    repo = "github";
    # renovate: datasource=terraform-provider depName=integrations/github
    version = "6.13.0";
    hash = "sha256-wKA8MUvOe68xZe+RCCG06HNcfnxOEDg3U2tT1stSLps=";
  };
  routeros = {
    owner = "terraform-routeros";
    repo = "routeros";
    # renovate: datasource=terraform-provider depName=terraform-routeros/routeros
    version = "1.99.1";
    hash = "sha256-JH34oqdFSq1l7fdBlITOuILzCipFPrmae2Mk56aDG1Q=";
  };
}
