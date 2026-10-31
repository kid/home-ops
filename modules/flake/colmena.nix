# `colmena apply --on <host> [switch|boot|test|dry-activate|build|push]` in the
# devshell — ongoing config push to an already-installed host over SSH (host
# must already exist via nixos-anywhere-install). Hosts opt in via
# fleet.colmena.deployment.<name>; nodes reuse the exact module list of
# nixosConfigurations.<name>, so colmena builds the same toplevel.
{
  inputs,
  lib,
  config,
  ...
}:
let
  allHosts = lib.foldl' (acc: system: acc // (config.den.hosts.${system} or { })) { } config.systems;

  # Tags every node gets from den data; hosts add their own on top via
  # fleet.colmena.deployment.<name>.tags.
  derivedTags =
    name:
    let
      host = allHosts.${name};
      k3s = host.k3s or { };
    in
    [ "env-${host.environment}" ]
    ++ lib.optionals (k3s ? clusterName) [
      "k3s"
      "k3s-${k3s.clusterName}"
      (if k3s ? serverHost then "k3s-agent" else "k3s-server")
    ];
in
{
  config.flake-file.inputs.colmena = {
    url = "github:nix-community/colmena";
    inputs.nixpkgs.follows = "nixpkgs";
    inputs.stable.follows = "nixpkgs";
  };

  options.fleet.colmena.deployment = lib.mkOption {
    type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
    default = { };
    description = "Per-host colmena `deployment.*` settings; only hosts listed here are colmena nodes";
  };

  config.flake.colmenaHive = inputs.colmena.lib.makeHive (
    {
      meta = {
        nixpkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
        # The flake-extended lib carries nixos versionSuffix/revision; without
        # it the toplevel differs from nixosConfigurations.<name>.
        specialArgs.lib = inputs.nixpkgs.lib;
      };
      # Root has no SSH keys on these hosts: log in as the invoking user and
      # escalate with (passwordless) sudo.
      defaults.deployment.targetUser = lib.mkDefault null;
    }
    // lib.mapAttrs (name: deployment: {
      # Two modules, so derived and hand-written tags concatenate.
      imports = config.flake.nixosConfigurations.${name}._module.args.modules ++ [
        { inherit deployment; }
        { deployment.tags = derivedTags name; }
      ];
    }) config.fleet.colmena.deployment
  );
}
