# Home-Ops Repository

This is an infrastructure-as-code (IaC) repository managing a home lab environment with Proxmox VMs, MikroTik RouterOS network devices, and a Talos Linux Kubernetes cluster.

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
├── clusters/lab/           # Kubernetes cluster definitions (ArgoCD apps)
└── test/                   # Go-based infrastructure tests
```

## Conventions

### OpenTofu/Terraform Files
- Use `.tofu` extension (not `.tf`)
- Prefix private files with underscore: `_variables.tofu`, `_versions.tofu`, `_outputs.tofu`
- Main logic goes in descriptively named files: `main.tofu`, `firewall.tofu`, `vlans.tofu`
- Use vim fold markers for variable grouping: `# Section Name {{{` and `# }}}`

### Terragrunt
- Stacks live in `tf-stacks/{env}/` directories
- Include shared providers from `tf-catalog/modules/_shared/`
- Use `root.hcl` in parent folders for common configuration
- Reference modules with double-slash syntax: `"${get_repo_root()}/tf-catalog/modules/proxmox//ros-lab"`

### Kubernetes
- ArgoCD manages cluster addons
- Helm charts vendored in `clusters/lab/addons/{addon}/charts/`
- Kustomize for customization

## Common Commands

```bash
# Prepare repo for development (eg run tofu init in all modules)
nix develop

# Run commands against lab stack
just lab plan
just lab apply

# Run commands against network stacks
just network plan
just network apply

# Bootstrap the lab (apply lab + configure network with default creds)
just bootstrap

# Reset lab VMs for recreation
just lab-reset

# Initialize all tofu modules for local development
just develop

# Run tests
just test

# Format code
nix fmt
```

## Important Notes

1. **Two environments**: `dev` (virtual lab on Proxmox) and `prd` (physical hardware)
2. **State backend**: Cloudflare R2 - ensure credentials are configured
3. **Secrets**: Don't touch secrets
4. **Talos**: Use `talosctl` for cluster management, configs in `clusterconfig/`
5. **Network**: RouterOS devices are managed as code - be careful with production changes
