# k3s behavior that modules/den/aspects/services/k3s/ relies on: token forms,
# which server may create the datastore, and how servers and agents join.
# These drive plain services.k3s, not the den aspects themselves.
{ pkgs }:
let
  inherit (pkgs) lib;

  common =
    { config, ... }:
    {
      virtualisation.memorySize = 2560;
      virtualisation.cores = 2;
      virtualisation.diskSize = 4096;
      networking.firewall.enable = false;
      # Started by the test, after it wrote /etc/k3s-token.
      systemd.services.k3s.wantedBy = lib.mkForce [ ];
      services.k3s = {
        enable = true;
        # Without it k3s picks the QEMU user-mode NIC, 10.0.2.15 on every
        # VM, as node and etcd peer address.
        extraFlags = [ "--node-ip=${config.networking.primaryIPAddress}" ];
      };
    };

  # No clusterInit/serverAddr/tokenFile here: a test sets K3S_CLUSTER_INIT,
  # K3S_URL and K3S_TOKEN_FILE at runtime, so one VM can change mode between
  # restarts and can start with no token at all.
  server = {
    imports = [ common ];
    services.k3s = {
      role = "server";
      extraFlags = [
        "--disable=coredns"
        "--disable=local-storage"
        "--disable=metrics-server"
        "--disable=traefik"
        "--disable=servicelb"
        "--flannel-backend=none"
        "--disable-network-policy"
        "--disable-kube-proxy"
      ];
    };
  };

  agent = {
    imports = [ common ];
    services.k3s = {
      role = "agent";
      serverAddr = "https://s1:6443";
      tokenFile = "/etc/k3s-token";
    };
  };

  helpers = ''
    pregenerated = "9f2c1e7a5b3d4f60812a7c9e4d6b1f3058a2c4e6f8091b3d5f7a9c0e2d4f6a81"

    def configure(node, token, env=[]):
        """Write the token file and the k3s mode (environment) of a node."""
        node.succeed("mkdir -p /run/systemd/system/k3s.service.d")
        # token None: no token file, the server generates its own token.
        if token is not None:
            node.succeed(f"printf '%s\n' '{token}' > /etc/k3s-token && chmod 600 /etc/k3s-token")
            env = env + ["K3S_TOKEN_FILE=/etc/k3s-token"]
        lines = "".join(f"Environment={e}\\n" for e in env)
        node.succeed(f"printf '[Service]\\n{lines}' > /run/systemd/system/k3s.service.d/mode.conf && systemctl daemon-reload")

    def start(node):
        node.succeed("systemctl restart --no-block k3s")

    def api_up(node):
        node.wait_until_succeeds("k3s kubectl get nodes", timeout=300)

    def joined(server, name):
        server.wait_until_succeeds(f"k3s kubectl get node {name}", timeout=420)

    def etcd_members(server, count):
        server.wait_until_succeeds(f"test $(k3s kubectl get nodes | grep -c 'control-plane,etcd') -eq {count}", timeout=600)
  '';

  mkTest =
    name: nodes: script:
    pkgs.testers.runNixOSTest {
      inherit name nodes;
      testScript = helpers + script;
    };
in
{
  # prd's case: the server generated its token, and later gets it back in a
  # token file (den.aspects.k3s-token), in the K10 form its node-token has.
  k3s-token-existing =
    mkTest "k3s-token-existing"
      {
        s1 = server;
        agentfull = agent;
        agentshort = agent;
      }
      ''
        start_all()
        configure(s1, None, ["K3S_CLUSTER_INIT=true"])
        start(s1)
        api_up(s1)
        full = s1.succeed("cat /var/lib/rancher/k3s/server/node-token").strip()
        secret = full.rsplit(":", 1)[1]
        assert full.startswith("K10") and "::server:" in full

        with subtest("the server restarts with its own token, K10 form, in a token file"):
            configure(s1, full, ["K3S_CLUSTER_INIT=true"])
            start(s1)
            api_up(s1)

        with subtest("an agent joins with the K10 form"):
            configure(agentfull, full)
            start(agentfull)
            joined(s1, "agentfull")

        with subtest("an agent joins with the bare secret"):
            configure(agentshort, secret)
            start(agentshort)
            joined(s1, "agentshort")

        with subtest("the server refuses a token other than the one it was bootstrapped with"):
            s1.succeed("systemctl stop k3s")
            configure(s1, pregenerated, ["K3S_CLUSTER_INIT=true"])
            start(s1)
            s1.wait_until_succeeds("journalctl -u k3s -b | grep -q 'encrypted with different token'", timeout=120)
            s1.fail("k3s kubectl get nodes")
      '';

  # A new cluster: provision-k3s-token's output, given to the server before
  # its first start and to the agent.
  k3s-token-pregenerated =
    mkTest "k3s-token-pregenerated"
      {
        s1 = server;
        inherit agent;
        intruder = agent;
      }
      ''
        start_all()
        configure(s1, pregenerated, ["K3S_CLUSTER_INIT=true"])
        start(s1)
        api_up(s1)
        full = s1.succeed("cat /var/lib/rancher/k3s/server/node-token").strip()
        assert full.endswith("::server:" + pregenerated), "the server did not adopt the pre-generated token"

        with subtest("an agent joins with the same token"):
            configure(agent, pregenerated)
            start(agent)
            joined(s1, "agent")

        with subtest("an agent with another token does not join"):
            configure(intruder, "0" * 64)
            start(intruder)
            intruder.sleep(60)
            s1.fail("k3s kubectl get node intruder")
      '';

  # k3s-server's rule with no initServer: a cluster's only server has
  # clusterInit; with a second one declared, none has it and each points at
  # another one.
  k3s-server-count =
    mkTest "k3s-server-count"
      {
        s1 = server;
        s2 = server;
      }
      ''
        start_all()
        with subtest("one server: cluster-init"):
            configure(s1, pregenerated, ["K3S_CLUSTER_INIT=true"])
            start(s1)
            etcd_members(s1, 1)

        with subtest("a second server joins through the first"):
            configure(s2, pregenerated, ["K3S_URL=https://s1:6443"])
            start(s2)
            etcd_members(s1, 2)

        with subtest("the first server loses cluster-init and points at the second"):
            s1.succeed("systemctl stop k3s")
            configure(s1, pregenerated, ["K3S_URL=https://s2:6443"])
            start(s1)
            etcd_members(s1, 2)
      '';

  # den.clusters.<name>.k3s.initServer: every server declared and started
  # together, and what that costs.
  k3s-init-server =
    mkTest "k3s-init-server"
      {
        s1 = server;
        s2 = server;
        s3 = server;
      }
      ''
        start_all()
        with subtest("three new servers form one cluster, the joiners started first"):
            for node in [s2, s3]:
                configure(node, pregenerated, ["K3S_URL=https://s1:6443"])
                start(node)
            s2.sleep(20)
            configure(s1, pregenerated, ["K3S_CLUSTER_INIT=true"])
            start(s1)
            etcd_members(s1, 3)

        with subtest("a wiped init server with the flag still set forms a second cluster"):
            s1.succeed("systemctl stop k3s; k3s-killall.sh || true")
            s1.succeed("rm -rf /var/lib/rancher/k3s /etc/rancher")
            start(s1)
            joined(s1, "s1")
            s1.sleep(30)
            etcd_members(s1, 1)
            etcd_members(s2, 3)
            uid = "k3s kubectl get node s1 -o jsonpath='{.metadata.uid}'"
            assert s1.succeed(uid) != s2.succeed(uid), "the rebuilt init server rejoined the old cluster"
      '';
}
