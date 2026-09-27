# MCP server for VictoriaMetrics, not yet packaged in nixpkgs. Vendored
# Go module (vendor/ committed upstream), so no separate vendorHash.
_: {
  perSystem =
    { pkgs, ... }:
    {
      packages.mcp-victoriametrics = pkgs.buildGoModule rec {
        pname = "mcp-victoriametrics";
        # renovate: datasource=github-releases depName=VictoriaMetrics/mcp-victoriametrics
        version = "1.20.2";

        src = pkgs.fetchFromGitHub {
          owner = "VictoriaMetrics";
          repo = "mcp-victoriametrics";
          rev = "v${version}";
          hash = "sha256-7kN7qwsvTL0scfBxMO/nrvikiysUxPY8nSFkhJsgGDM=";
        };

        vendorHash = null;
        subPackages = [ "cmd/mcp-victoriametrics" ];

        meta = {
          description = "MCP server for VictoriaMetrics";
          homepage = "https://github.com/VictoriaMetrics/mcp-victoriametrics";
          license = pkgs.lib.licenses.asl20;
          mainProgram = "mcp-victoriametrics";
        };
      };
    };
}
