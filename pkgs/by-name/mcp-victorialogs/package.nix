# MCP server for VictoriaLogs, not yet packaged in nixpkgs. Vendored
# Go module (vendor/ committed upstream), so no separate vendorHash.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "mcp-victorialogs";
  # renovate: datasource=github-releases depName=VictoriaMetrics/mcp-victorialogs
  version = "1.9.0";

  src = fetchFromGitHub {
    owner = "VictoriaMetrics";
    repo = "mcp-victorialogs";
    rev = "v${version}";
    hash = "sha256-esfd6Eg1j2BCgee1T5tiIdSPWVEBqhI4UGDKRFYyn3s=";
  };

  vendorHash = null;
  subPackages = [ "cmd/mcp-victorialogs" ];

  meta = {
    description = "MCP server for VictoriaLogs";
    homepage = "https://github.com/VictoriaMetrics/mcp-victorialogs";
    license = lib.licenses.asl20;
    mainProgram = "mcp-victorialogs";
  };
}
