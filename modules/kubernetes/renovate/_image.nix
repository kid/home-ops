# Renovate's executor image for renovate-operator (./default.nix): nixpkgs'
# renovate plus a single-user Nix whose store is the image's own /nix, owned
# by the uid the operator runs its pods as, so postUpgradeTasks can run
# `nix run .#…` in the repo being updated. The operator rejects hostPath,
# so the node's Nix daemon is out of reach; every run starts from this store.
{
  callPackage,
  dockerTools,
  writeTextDir,
  renovate,
  nix,
  git,
  coreutils,
  gnugrep,
  gnused,
  findutils,
  gnutar,
  gzip,
}:
let
  # renovate-operator's pod uid/gid.
  uid = 12021;
  gid = 12021;
in
dockerTools.streamLayeredImage {
  name = "home-ops-renovate";
  inherit uid gid;
  uname = "renovate";
  gname = "renovate";
  includeNixDB = true;
  contents = [
    renovate
    nix
    git
    coreutils
    gnugrep
    gnused
    findutils
    gnutar
    gzip
    (callPackage ./_refresh-nix-hash.nix { })
    dockerTools.binSh
    dockerTools.usrBinEnv
    dockerTools.caCertificates
    (dockerTools.fakeNss.override {
      extraPasswdLines = [ "renovate:x:${toString uid}:${toString gid}:renovate:/tmp:/bin/sh" ];
      extraGroupLines = [ "renovate:x:${toString gid}:" ];
    })
    (writeTextDir "etc/nix/nix.conf" ''
      experimental-features = nix-command flakes pipe-operators
      build-users-group =
      sandbox = false
    '')
  ];
  # The store layers already belong to uid/gid; the top layer's /nix dirs
  # and the database extraCommands writes would otherwise be root's.
  fakeRootCommands = ''
    mkdir -p nix/store nix/var/nix/gcroots nix/var/nix/profiles
    chown -R ${toString uid}:${toString gid} nix
  '';
  config = {
    User = "${toString uid}:${toString gid}";
    WorkingDir = "/tmp";
    Env = [
      "PATH=/bin"
      "HOME=/tmp"
      "USER=renovate"
      "NIX_PAGER=cat"
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
    ];
    Labels."org.opencontainers.image.source" = "https://github.com/kid/home-ops";
  };
}
