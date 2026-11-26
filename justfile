[positional-arguments]
tf path *args:
    shift; secretspec run terragrunt --working-dir "{{ path }}" run --source-update -- "$@"

[positional-arguments]
tf-all path *args:
    shift; secretspec run terragrunt --working-dir "{{ path }}" run --source-update --all -- "$@"

plan path: (tf path "plan")

plan-all path: (tf-all path "plan")

apply path: (tf path "apply")

apply-all path: (tf-all path "apply")

hostname := `hostname -s`
nh := if os() == "macos" { "nh darwin" } else { "nh os" }

build host=hostname *args:
    {{ nh }} build . --hostname {{ host }} {{ args }}

test host=hostname *args:
    {{ nh }} test . --hostname {{ host }} --ask {{ args }}

switch host=hostname *args:
    {{ nh }} switch . --hostname {{ host }} --ask {{ args }}

boot host=hostname *args:
    {{ nh }} boot . --hostname {{ host }} --ask {{ args }}
