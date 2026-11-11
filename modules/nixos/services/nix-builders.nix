# Nix builders and their caches, discovered from host data. A builder is any
# den.hosts entry with a freeform `nix-builder = { maxJobs; speedFactor;
# minFreeGiB; maxFreeGiB; }` attr: it serves its store as a signed harmonia
# cache on :5000 (key in secrets/hosts/<host>/nix-cache-key.{sops,pub}) and
# accepts ssh-ng builds as the trusted `nix-remote-builder` user.
#
# Every host substitutes from the builders it shares a network with. A routed
# client (`nix-builder-client.routed = true`, e.g. the CI runner) reaches every
# builder's primary address through rb5009's forward rules
# (modules/routerosDevices/rb5009.nix) instead. Builders and routed clients
# also remote-build on the builders they reach, authenticating with their own
# SSH host key (secrets/hosts/<host>/ssh_host_ed25519_key.pub).
{
  config,
  inputs,
  lib,
  ...
}:
let
  allHosts = lib.foldl' (acc: system: acc // (config.den.hosts.${system} or { })) { } config.systems;
  builders = lib.filterAttrs (_: h: h ? nix-builder) allHosts;
  isRoutedClient = name: allHosts.${name}.nix-builder-client.routed or false;
  networksOf = name: map (i: i.network) (config.den.devices.${name}.interfaces or [ ]);
  # How `name` reaches builder `b`: b's address on the first network they
  # share; else, for a routed client, b's primary address; else unreachable
  # (null).
  reach =
    name: b:
    let
      shared = lib.findFirst (
        i: lib.elem i.network (networksOf name)
      ) null config.den.devices.${b}.interfaces;
    in
    if shared != null then
      shared.address
    else if isRoutedClient name then
      config.den.devices.${b}.address
    else
      null;
  peersOf =
    name:
    lib.attrNames builders
    |> lib.filter (b: b != name)
    |> map (b: {
      name = b;
      address = reach name b;
    })
    |> lib.filter (p: p.address != null);
  # Hosts allowed to build on `b`: the other builders, plus routed clients.
  buildClientsOf =
    b:
    (lib.attrNames builders |> lib.filter (n: n != b))
    ++ (lib.attrNames allHosts |> lib.filter isRoutedClient);
  secretsDir = ../../../secrets/hosts;
  readKey = path: builtins.readFile path |> lib.removeSuffix "\n";
  gib = n: n * 1024 * 1024 * 1024;
in
{
  den.aspects.nix-cache.nixos =
    { host, ... }:
    let
      peers = peersOf host.name;
      buildsRemotely = builders ? ${host.name} || isRoutedClient host.name;
    in
    {
      config = lib.mkMerge [
        {
          nix.settings.extra-substituters = map (p: "http://${p.address}:5000") peers;
          nix.settings.extra-trusted-public-keys = map (
            p: readKey (secretsDir + "/${p.name}/nix-cache-key.pub")
          ) peers;
        }
        (lib.mkIf (buildsRemotely && peers != [ ]) {
          nix.distributedBuilds = true;
          nix.settings.builders-use-substitutes = true;
          nix.buildMachines = map (p: {
            hostName = p.address;
            sshUser = "nix-remote-builder";
            sshKey = "/etc/ssh/ssh_host_ed25519_key";
            protocol = "ssh-ng";
            system = "x86_64-linux";
            inherit (builders.${p.name}.nix-builder) maxJobs speedFactor;
            supportedFeatures = [
              "kvm"
              "nixos-test"
              "big-parallel"
              "benchmark"
            ];
          }) peers;
          programs.ssh.knownHosts =
            peers
            |> map (
              p:
              lib.nameValuePair "nix-builder-${p.name}" {
                hostNames = [ p.address ];
                publicKeyFile = secretsDir + "/${p.name}/ssh_host_ed25519_key.pub";
              }
            )
            |> lib.listToAttrs;
        })
      ];
    };

  den.aspects.nix-builder.nixos =
    { host, config, ... }:
    let
      self = builders.${host.name}.nix-builder;
    in
    {
      imports = [ inputs.sops-nix.nixosModules.sops ];

      config = lib.mkIf (builders ? ${host.name}) {
        # Builders are impermanent; the /etc/ssh bind mount isn't guaranteed
        # to be up when sops-nix activates.
        sops.age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
        sops.secrets.nix-cache-key = {
          sopsFile = secretsDir + "/${host.name}/nix-cache-key.sops";
          format = "binary";
        };

        services.harmonia.cache = {
          enable = true;
          signKeyPaths = [ config.sops.secrets.nix-cache-key.path ];
        };
        # Only exists with sops.useSystemdActivation; a no-op otherwise.
        systemd.services.harmonia = {
          after = [ "sops-install-secrets.service" ];
          wants = [ "sops-install-secrets.service" ];
        };
        # Global: NIC names are hardware-derived.
        networking.firewall.allowedTCPPorts = [ 5000 ];

        # The user half of srvos's roles/nix-remote-builder.nix, not imported:
        # its hourly nix.gc would empty the cache.
        users.users.nix-remote-builder = {
          isNormalUser = true;
          group = "nogroup";
          openssh.authorizedKeys.keys = map (
            c:
            ''restrict,command="nix-daemon --stdio" ${readKey (secretsDir + "/${c}/ssh_host_ed25519_key.pub")}''
          ) (buildClientsOf host.name);
        };
        nix.settings.trusted-users = [ "nix-remote-builder" ];
        services.openssh.settings.MaxStartups = 100;

        # Nix GCs only below min-free. Never add nix.gc.automatic: a scheduled
        # GC deletes every unrooted path, emptying the cache.
        nix.settings.min-free = gib self.minFreeGiB;
        nix.settings.max-free = gib self.maxFreeGiB;
      };
    };
}
