# Home-Ops Repository

This repo is infrastructure-as-code for a home lab: Proxmox VMs, MikroTik RouterOS network, and a Talos Kubernetes cluster. Agents should be conservative and safe; production changes exist alongside dev.

## Source of Truth for Agent Rules

- There are no `.cursor/rules/`, `.cursorrules`, or `.github/copilot-instructions.md` files in this repo. This document is the primary agent guidance.

## Technology Stack

| Category | Technologies |
|----------|-------------|
| **IaC** | OpenTofu (uses `.tofu` extension, not `.tf`), Terragrunt |
| **Virtualization** | Proxmox VE |
| **Kubernetes** | Talos Linux, ArgoCD, Cilium CNI, cert-manager, Helm, Kustomize |
| **Networking** | MikroTik RouterOS (RB5009, CRS320, CHR) |
| **Secrets** | SOPS with age encryption |
| **Dev Environment** | Nix Flakes, direnv |
| **Task Runner** | just (justfile) |
| **State Backend** | Cloudflare R2 (S3-compatible) |
| **Testing** | Go with Terratest |

## Directory Structure

```
home-ops/
├── tf-catalog/modules/     # Reusable OpenTofu modules
│   ├── proxmox/            # Proxmox VM provisioning
│   ├── proxmox-talos-cluster/  # Talos cluster on Proxmox
│   ├── ros/                # RouterOS modules (base, firewall, dhcp, dns, qos, capsman)
│   └── _shared/            # Shared provider configurations
├── tf-stacks/              # Terragrunt stacks (environment deployments)
│   ├── dev/                # Development: lab VMs, network, Talos cluster
│   └── prd/                # Production: physical RB5009 router, CRS320 switch
├── kubernetes/             # Flux-managed cluster apps and kustomizations
└── test/                   # Go-based infrastructure tests
```

## Build, Lint, and Test Commands

### Environment and Bootstrap

```bash
# Enter dev shell
nix develop

# Initialize tofu modules (loops through modules)
just develop
```

### Terragrunt (Lab and Network)

```bash
# Run plan/apply for lab stack
just lab plan
just lab apply

# Run plan/apply for network stacks
just network plan
just network apply
```

### Tests (Go / Terratest)

```bash
# Run all tests in ./test
just test

# Run all tests with go directly
go test -v ./test

# Run a single test by name
go test -v ./test -run '^TestSsh$'

# Run a single subtest (example)
go test -v ./test -run '^TestSsh$/trusted1$'
```

### Formatting and Linting

```bash
# Format everything via nix (preferred)
nix fmt

# Go formatting (if needed directly)
gofmt -w test/*.go
```

There is no repo-specific Go linter config; keep changes gofmt-compliant and follow existing patterns.

## Code Style and Conventions

### General

- Follow `.editorconfig` defaults: 2 spaces, final newline, trim trailing whitespace.
- Go files use tabs; Markdown uses 4-space indent and does not trim trailing whitespace.
- Prefer minimal, explicit changes; avoid reformatting unrelated code.

### OpenTofu (`.tofu`)

- Use `.tofu` extension, never `.tf`.
- Private file naming: `_variables.tofu`, `_versions.tofu`, `_outputs.tofu`.
- Put main logic in descriptive files (`main.tofu`, `firewall.tofu`, `vlans.tofu`).
- Use vim fold markers for variable grouping:
  - Start: `# Section Name {{{`
  - End: `# }}`}
- Keep provider configuration in `tf-catalog/modules/_shared/` and referenced by modules.
- Use clear, stable names for resources and avoid reordering blocks without reason.

### Terragrunt (`.hcl`)

- Stacks live under `tf-stacks/{env}/` with `root.hcl` for shared config.
- Use `read_terragrunt_config(find_in_parent_folders(...))` for shared inputs.
- Module sources should use the double-slash pattern:
  - `"${get_repo_root()}/tf-catalog/modules/proxmox//ros-lab"`
- Favor `try()` for optional inputs and keep locals grouped by purpose.

### Kubernetes Manifests (YAML)

- Kustomize and Flux manage cluster apps; keep manifests declarative.
- Avoid inline secrets; use ExternalSecrets or SOPS-encrypted files.
- Preserve existing kustomization structure and app layouts.

### Go Tests

- Keep tests under `test/` and use package `test`.
- Prefer `t.Run` subtests for target-specific scenarios.
- Use `t.Fatalf` for setup failures; assertions (`assert`) for expected behavior.
- Keep retry logic via Terratest retry helpers to handle transient device state.

### Imports

- Let `gofmt` order imports; standard library first, then third-party.
- Group imports by blank lines only when gofmt does it; do not hand-align.

### Naming

- Use descriptive names for stacks, resources, and modules.
- Go: `CamelCase` for exported identifiers, `mixedCase` for locals.
- Avoid abbreviations unless standard in infra (e.g., `ros`, `oob`).

### Error Handling

- Fail fast in tests on setup errors with `t.Fatalf`.
- In infra config, prefer explicit errors over silent fallbacks; use `try()` only where optional input is expected.

## Secrets and Safety

- Secrets live under `secrets/` and are SOPS-encrypted; do not modify without explicit instruction.
- Never commit decrypted secrets or generated `*.tfstate`/`kubeconfig`/`talosconfig` files.
- Be careful with production (`tf-stacks/prd/`) changes; highlight when edits touch prod.

## Common Tasks

```bash
# Bootstrap lab and apply network with default creds
just bootstrap-lab

# Reset lab VMs (taints) and clear network state
just lab-reset

# Clear state for a stack
just clear-stack-state stack=dev/lab
```

## Notes for Agents

- Two environments exist: `dev` (virtual lab) and `prd` (physical hardware).
- State backend is Cloudflare R2; credentials must be present in SOPS secrets.
- Talos management uses `talosctl`; configs are in `talos/` and `clusterconfig/` (when present).
- RouterOS config is code-driven; avoid destructive changes unless asked.
