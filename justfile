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
