# IPv4 CIDR arithmetic — nixpkgs has no built-in equivalent of Terraform's
# cidrsubnet()/cidrhost(). Used by modules/den/schema/networks.nix to compute
# each VLAN's subnet from environment.cidrBase + vlanId/prefix, the same
# formula tf-stacks/prd/env.hcl's `vlans` local used:
#   cidrsubnet(env_cidr, prefix - env_cidr_prefix, vlan_id)
{ lib, ... }:
let
  pow2 = n: if n == 0 then 1 else 2 * pow2 (n - 1);

  ipToInt =
    ip:
    let
      parts = map lib.toInt (lib.splitString "." ip);
    in
    (builtins.elemAt parts 0) * 16777216
    + (builtins.elemAt parts 1) * 65536
    + (builtins.elemAt parts 2) * 256
    + (builtins.elemAt parts 3);

  intToIp =
    i:
    let
      o1 = i / 16777216;
      r1 = i - o1 * 16777216;
      o2 = r1 / 65536;
      r2 = r1 - o2 * 65536;
      o3 = r2 / 256;
      o4 = r2 - o3 * 256;
    in
    "${toString o1}.${toString o2}.${toString o3}.${toString o4}";

  parseCidr =
    cidr:
    let
      parts = lib.splitString "/" cidr;
    in
    {
      base = ipToInt (builtins.elemAt parts 0);
      prefixLength = lib.toInt (builtins.elemAt parts 1);
    };

  # cidrsubnet(prefix, newbits, netnum): carve a /(prefixLength+newbits)
  # subnet out of `prefix`, at position `netnum`.
  cidrsubnet =
    prefix: newbits: netnum:
    let
      p = parseCidr prefix;
      newPrefixLength = p.prefixLength + newbits;
      subnetBase = p.base + netnum * pow2 (32 - newPrefixLength);
    in
    "${intToIp subnetBase}/${toString newPrefixLength}";

  # cidrhost(prefix, hostnum): the host address `hostnum` within `prefix`.
  # A negative hostnum counts back from the end of the range.
  cidrhost =
    prefix: hostnum:
    let
      p = parseCidr prefix;
      hostBits = 32 - p.prefixLength;
      effectiveHostnum = if hostnum < 0 then pow2 hostBits + hostnum else hostnum;
    in
    intToIp (p.base + effectiveHostnum);

  prefixLength = cidr: (parseCidr cidr).prefixLength;
in
{
  # Exposed as a module arg (`{ cidrLib, ... }:`) to any other flake-parts
  # module, top-level or perSystem — not just modules/den/schema/networks.nix.
  _module.args.cidrLib = {
    inherit cidrsubnet cidrhost prefixLength;
  };
}
