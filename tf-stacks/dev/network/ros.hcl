inputs = yamldecode(sops_decrypt_file("${get_repo_root()}/secrets/dev/routeros.sops.yaml"))
