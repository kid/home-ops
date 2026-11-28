# OpenTofu on a tofu stack (modules/den/batteries/tofu), named after its
# directory under tf-stacks/ with dashes, e.g. `just tofu prd-k3s plan`.
[positional-arguments]
tofu stack *args:
    shift; secretspec run nix run ".#tofu-{{ stack }}" -- "$@"

hostname := `hostname -s`
nh := if os() == "macos" { "nh darwin" } else { "nh os" }
# kid/nixfiles-work, swapped in for the stub at ./private when checked out.
private_dir := env("NIXFILES_PRIVATE", home_directory() / "Code/kid/nixfiles-work")
private := if path_exists(private_dir) == "true" { "--override-input private git+file://" + private_dir } else { "" }

build host=hostname *args:
    {{ nh }} build . --hostname {{ host }} {{ private }} {{ args }}

test host=hostname *args:
    {{ nh }} test . --hostname {{ host }} {{ private }} --ask {{ args }}

switch host=hostname *args:
    {{ nh }} switch . --hostname {{ host }} {{ private }} --ask {{ args }}

boot host=hostname *args:
    {{ nh }} boot . --hostname {{ host }} {{ private }} --ask {{ args }}
