# VM tests of the k3s den aspects (modules/nixos/services/k3s/). Each
# test evaluates this repo's module tree a second time with a fixture cluster
# and fixture hosts added, and boots the hosts' real den-resolved NixOS
# modules (host.mainModule), so the flags come from the aspects.
{
  pkgs,
  inputs,
  modulesTree,
}:
let
  inherit (pkgs) lib;

  token = "9f2c1e7a5b3d4f60812a7c9e4d6b1f3058a2c4e6f8091b3d5f7a9c0e2d4f6a81";

  # A throwaway age key and the cluster token encrypted to it, made at build
  # time, so k3s-token's sops path runs for real with no key in the repo.
  secrets =
    pkgs.runCommand "k3s-test-secrets"
      {
        nativeBuildInputs = [
          pkgs.age
          pkgs.sops
        ];
      }
      ''
        mkdir $out
        age-keygen -o $out/key.txt 2>/dev/null
        printf '%s\n' '${token}' > token
        sops encrypt --age "$(age-keygen -y $out/key.txt)" \
          --input-type binary --output-type binary token > $out/k3s-token.sops
      '';

  # servers/agents: fixture host names, also the test node names. hostBase:
  # their K3s host numbers are hostBase + 1, + 2, ... in that order.
  fixture =
    {
      servers,
      agents ? [ ],
      initServer ? null,
      hostBase ? 200,
    }:
    { den, config, ... }:
    let
      names = servers ++ agents;
      index = name: (lib.lists.findFirstIndex (n: n == name) null names) + 1;
    in
    {
      den.clusters.test = {
        environment = "prd";
        network = "K3s";
        networks.pods.cidr = "172.50.0.0/16";
        networks.services.cidr = "172.52.0.0/16";
        k3s = { inherit initServer; };
      };

      den.hosts.x86_64-linux = lib.genAttrs names (name: {
        # Only a test node, not a nixosConfigurations output.
        intoAttr = [ ];
        environment = "prd";
        k3s = {
          clusterName = "test";
        }
        // lib.optionalAttrs (lib.elem name agents) { serverHost = lib.head servers; };
      });

      den.devices = lib.genAttrs names (name: {
        interfaces = [
          {
            network = "K3s";
            hostNum = hostBase + index name;
            mac = "52:54:00:99:00:0${toString (index name)}";
          }
        ];
      });

      den.aspects = lib.genAttrs names (name: {
        includes = [
          (if lib.elem name agents then den.aspects.k3s-agent else den.aspects.k3s-server)
          den.aspects.k3s-token
          den.aspects.k3s-cilium
        ];

        nixos = {
          networking.hostName = name;
          # The aspects address nodes by their den.devices address.
          networking.interfaces.eth1.ipv4.addresses = [
            {
              inherit (config.den.devices.${name}) address;
              prefixLength = 24;
            }
          ];

          # sops-nix refuses a key file in the store; copy it before it runs.
          system.activationScripts.k3s-test-key.text = "install -m 600 ${secrets}/key.txt /run/k3s-test-key";
          system.activationScripts.setupSecrets.deps = [ "k3s-test-key" ];
          sops = {
            age.keyFile = "/run/k3s-test-key";
            age.sshKeyPaths = lib.mkForce [ ];
            gnupg.sshKeyPaths = lib.mkForce [ ];
            validateSopsFiles = false;
            secrets.k3s-token.sopsFile = lib.mkForce "${secrets}/k3s-token.sops";
          };

          virtualisation.memorySize = 2560;
          virtualisation.cores = 2;
          virtualisation.diskSize = 4096;
          system.switch.enable = true;
          system.stateVersion = "26.05";
        };
      });
    };

  # The den-resolved NixOS module of each fixture host.
  hostModules =
    args:
    let
      eval = inputs.flake-parts.lib.evalFlakeModule { inherit inputs; } {
        imports = [
          modulesTree
          (fixture args)
        ];
      };
    in
    eval.config.den.hosts.x86_64-linux
    |> lib.getAttrs (args.servers ++ (args.agents or [ ]))
    |> lib.mapAttrs (_: host: host.mainModule);

  helpers = ''
    def etcd_members(server, count):
        server.wait_until_succeeds(f"test $(k3s kubectl get nodes | grep -c 'control-plane,etcd') -eq {count}", timeout=600)

    def k3s_args(node):
        return node.succeed("systemctl show -p ExecStart --value k3s")
  '';
in
{
  # den.clusters.<name>.k3s.initServer: three servers and an agent, all
  # declared and all started at boot, with the token from sops.
  k3s-init-server = pkgs.testers.runNixOSTest {
    name = "k3s-init-server";
    nodes = hostModules {
      servers = [
        "s1"
        "s2"
        "s3"
      ];
      agents = [ "a1" ];
      initServer = "s1";
    };
    testScript = helpers + ''
      start_all()
      etcd_members(s1, 3)
      s1.wait_until_succeeds("k3s kubectl get node a1", timeout=420)
      print(s1.succeed("k3s kubectl get nodes -o wide"))

      with subtest("the aspects gave each node its role"):
          assert "--cluster-init" in k3s_args(s1) and "--server https://" not in k3s_args(s1)
          for node in [s2, s3]:
              assert "--cluster-init" not in k3s_args(node)
              assert "--server https://10.0.40.201:6443" in k3s_args(node)
          assert "--server https://10.0.40.201:6443" in k3s_args(a1)
          assert "--lb-server-port=6443" in k3s_args(a1)

      with subtest("the server adopted the token from sops"):
          assert s1.succeed("cat /var/lib/rancher/k3s/server/node-token").strip().endswith("::server:${token}")
          assert s1.succeed("cat /run/secrets/k3s-token").strip() == "${token}"
    '';
  };

  # No initServer: the server-count rule. s1 is the cluster's only declared
  # server; then s2 is declared too, and s1 switches to that configuration.
  k3s-server-count =
    let
      one = hostModules { servers = [ "s1" ]; };
      two = hostModules {
        servers = [
          "s1"
          "s2"
        ];
      };
    in
    pkgs.testers.runNixOSTest {
      name = "k3s-server-count";
      nodes = {
        inherit (one) s1;
        inherit (two) s2;
        # s1 in the two-server registry: never booted, only switched to.
        s1two = two.s1;
      };
      testScript =
        { nodes, ... }:
        helpers
        + ''
          s1.start()
          with subtest("the only declared server creates the cluster"):
              etcd_members(s1, 1)
              assert "--cluster-init" in k3s_args(s1)

          with subtest("a second declared server joins the first"):
              s2.start()
              etcd_members(s1, 2)
              assert "--cluster-init" not in k3s_args(s2)
              assert "--server https://10.0.40.201:6443" in k3s_args(s2)

          with subtest("the first server switches to the two-server configuration"):
              s1.succeed("${nodes.s1two.system.build.toplevel}/bin/switch-to-configuration test >&2")
              assert "--cluster-init" not in k3s_args(s1)
              assert "--server https://10.0.40.202:6443" in k3s_args(s1)
              etcd_members(s1, 2)
              etcd_members(s2, 2)
        '';
    };

  # A single-server (embedded etcd) cluster and an agent change K3s
  # addresses (.201/.202 → .241/.242), as prd's nodes do: etcd keeps its
  # old peer URL until a --cluster-reset, which keeps the data.
  k3s-renumber =
    let
      before = hostModules {
        servers = [ "s1" ];
        agents = [ "a1" ];
      };
      after = hostModules {
        servers = [ "s1" ];
        agents = [ "a1" ];
        hostBase = 240;
      };
    in
    pkgs.testers.runNixOSTest {
      name = "k3s-renumber";
      nodes = {
        inherit (before) s1 a1;
        # Never booted, only switched to.
        s1new = after.s1;
        a1new = after.a1;
      };
      testScript =
        { nodes, ... }:
        helpers
        + ''
          s1.start()
          a1.start()
          etcd_members(s1, 1)
          s1.wait_until_succeeds("k3s kubectl get node a1", timeout=420)
          s1.succeed("k3s kubectl create configmap renumber-probe --from-literal=kept=yes")

          with subtest("the server's new node-ip makes etcd refuse to start"):
              # The switch waits on k3s's start job, which never finishes
              # (on prd: `colmena apply … boot` and a reboot instead).
              s1.execute("timeout 120 ${nodes.s1new.system.build.toplevel}/bin/switch-to-configuration test >&2")
              s1.execute("ip addr del 10.0.40.201/24 dev eth1")
              s1.succeed("ip -4 addr show eth1 | grep -q 10.0.40.241")
              assert "--node-ip=10.0.40.241" in k3s_args(s1)
              s1.wait_until_succeeds("journalctl -u k3s | grep -q 'not a member of the etcd cluster'", timeout=300)

          with subtest("--cluster-reset with the unit's own command line recovers it"):
              s1.succeed("systemctl stop k3s")
              argv = s1.succeed("systemctl show -p ExecStart --value k3s").split("argv[]=")[1].split(" ;")[0]
              _, out = s1.execute(argv + " --cluster-reset 2>&1")
              assert "Managed etcd cluster membership has been reset" in out, out
              s1.succeed("systemctl start k3s")
              s1.wait_until_succeeds("k3s kubectl get node s1", timeout=300)
              s1.wait_until_succeeds("test \"$(k3s kubectl get node s1 -o jsonpath='{.status.addresses[?(@.type==\"InternalIP\")].address}')\" = 10.0.40.241", timeout=300)
              assert s1.succeed("k3s kubectl get configmap renumber-probe -o jsonpath='{.data.kept}'").strip() == "yes"
              etcd_members(s1, 1)

          with subtest("the agent rejoins at the server's new address"):
              a1.execute("${nodes.a1new.system.build.toplevel}/bin/switch-to-configuration test >&2")
              a1.execute("ip addr del 10.0.40.202/24 dev eth1")
              assert "--server https://10.0.40.241:6443" in k3s_args(a1)
              s1.wait_until_succeeds("test \"$(k3s kubectl get node a1 -o jsonpath='{.status.addresses[?(@.type==\"InternalIP\")].address}')\" = 10.0.40.242", timeout=420)
        '';
    };
}
