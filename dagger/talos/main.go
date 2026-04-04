package main

import (
	"context"
	"dagger/talos/internal/dagger"
	"errors"
	"fmt"
	"strings"
	"time"
)

const talosctlPath = "/usr/local/bin/talosctl"

type Talos struct {
	Configs *dagger.Directory
	EnvFile *dagger.File
	Secrets *dagger.Secret
	Cfg     *TalosConfig
}

func New(
	ctx context.Context,
	configs *dagger.Directory,
	envFile *dagger.File,
	secrets *dagger.Secret,
) (*Talos, error) {
	cfg, err := loadConfig(ctx, configs)
	if err != nil {
		return nil, fmt.Errorf("failed to load talos config: %w", err)
	}

	return &Talos{
		Configs: configs,
		EnvFile: envFile,
		Secrets: secrets,
		Cfg:     cfg,
	}, err
}

func (m *Talos) Schematic(ctx context.Context) (string, error) {
	fileName := "schematic.yaml"
	schematic, err := dag.
		Wolfi().
		Container(dagger.WolfiContainerOpts{Packages: []string{"curl", "jq"}}).
		WithFile(fileName, m.Configs.File(fileName)).
		WithExec([]string{"curl", "-sX", "POST", "--data-binary", "@-", "https://factory.talos.dev/schematics"}, dagger.ContainerWithExecOpts{
			RedirectStdin:  fileName,
			RedirectStdout: "/tmp/result.json",
		}).
		WithExec([]string{"jq", "-r", ".id"}, dagger.ContainerWithExecOpts{
			RedirectStdin: "/tmp/result.json",
		}).
		Stdout(ctx)
	if err != nil {
		return "", fmt.Errorf("failed to get schematic ID: %w", err)
	}
	return strings.TrimSpace(schematic), nil
}

func (m *Talos) InstallerImage(ctx context.Context) (string, error) {
	schematic, err := m.Schematic(ctx)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("factory.talos.dev/%s-installer/%s:%s", m.Cfg.Target, schematic, m.Cfg.TalosVersion), nil
}

func (m *Talos) MachineConfig(
	ctx context.Context,
	// +optional
	nodeName string,
) (*dagger.Secret, error) {
	nodeType, err := m.Cfg.nodeType(nodeName)
	if err != nil {
		return nil, err
	}

	destination := fmt.Sprintf("/tmp/%s.yaml", nodeName)

	installer, err := m.InstallerImage(ctx)
	if err != nil {
		return nil, err
	}

	args := []string{
		"talosctl", "gen", "config", m.Cfg.ClusterName, m.Cfg.ClusterEndpoint,
		fmt.Sprintf("--output-types=%s", nodeType), fmt.Sprintf("--output=%s", destination),
		fmt.Sprintf("--install-image=%s", installer),
		"--with-secrets=/secrets.yaml",
		"--with-docs=false",
		"--with-examples=false",
		"--with-kubespan=false",
	}

	patches, err := m.Cfg.patchesFor(nodeName)
	if err != nil {
		return nil, err
	}

	for _, patchPath := range patches {
		args = append(args, fmt.Sprintf("--config-patch=@/src/%s", patchPath))
	}

	ctr := m.baseContainer().
		WithMountedSecret("/secrets.yaml", m.Secrets).
		WithDirectory("/src", m.Configs).
		WithExec(args).
		WithEnvFileVariables(m.EnvFile.AsEnvFile()).
		WithExec([]string{"envsubst"}, dagger.ContainerWithExecOpts{
			RedirectStdin: destination,
		})

	machineConfigContents, err := ctr.Stdout(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to generate machine config: %w", err)
	}

	return dag.SetSecret(machineConfigSecretName(nodeName), machineConfigContents), nil
}

// +check
func (m *Talos) Validate(
	ctx context.Context,
	// +optional
	node string,
) error {
	if m.Secrets == nil {
		return fmt.Errorf("talosSecrets is required for validation")
	}

	for _, n := range m.Cfg.Nodes {
		if node != "" && n.Hostname != node {
			continue
		}

		machineCfg, err := m.MachineConfig(ctx, n.Hostname)
		if err != nil {
			return fmt.Errorf("failed to generate machine config for validation: %w", err)
		}

		_, err = m.baseContainer().
			WithMountedSecret("/machineconfig.yaml", machineCfg).
			WithExec([]string{"talosctl", "validate", "-c", "/machineconfig.yaml", "-m", "metal", "--strict"}).
			Sync(ctx)
		if err != nil {
			return fmt.Errorf("validation failed for node %s: %w", n.Hostname, err)
		}
	}

	return nil
}

// +cache="never"
func (m *Talos) TalosConfig(ctx context.Context) (*dagger.Secret, error) {
	endpoints := m.Cfg.controlPlaneIPs()
	nodes := m.Cfg.nodeIPs()
	script := buildTalosConfigScript(m.Cfg, endpoints, nodes)

	ctr := m.baseContainer().
		WithMountedSecret("/secrets.yaml", m.Secrets).
		WithMountedTemp("/work").
		WithExec([]string{"sh", "-ec", script})

	talosConfigContents, err := ctr.Stdout(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to generate talos config: %w", err)
	}

	return dag.SetSecret("talosconfig", talosConfigContents), nil
}

func (m *Talos) Container(ctx context.Context) (*dagger.Container, error) {
	talosCfg, err := m.TalosConfig(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to generate talos config for runtime container: %w", err)
	}

	return m.baseContainer().
		WithMountedSecret("/talosconfig.yaml", talosCfg).
		WithEnvVariable("TALOSCONFIG", "/talosconfig.yaml").
		WithEnvVariable("TERM", "xterm-256color").
		Sync(ctx)
}

// +cache="never"
func (m *Talos) Apply(
	ctx context.Context,
	// +default=false
	insecure bool,
	node string,
) error {
	if strings.TrimSpace(node) == "" {
		return fmt.Errorf("node is required")
	}

	nodeIP, err := m.Cfg.nodeIPByName(node)
	if err != nil {
		return err
	}

	machineCfg, err := m.MachineConfig(ctx, node)
	if err != nil {
		return fmt.Errorf("failed to generate machine config for apply: %w", err)
	}

	args := []string{"talosctl", "apply", "-f", "/machineconfig.yaml", "--nodes", nodeIP}
	if insecure {
		args = append(args, "--insecure")
	}

	runtimeCtr, err := m.Container(ctx)
	if err != nil {
		return fmt.Errorf("failed to create talos runtime container: %w", err)
	}

	_, err = runtimeCtr.
		WithMountedSecret("/machineconfig.yaml", machineCfg).
		WithEnvVariable("CACHEBUSTER", time.Now().String()).
		WithExec(args).
		Sync(ctx)

	return err
}

// +cache="never"
func (m *Talos) ApplyAll(
	ctx context.Context,
	// +default=false
	insecure bool,
) error {
	for _, node := range m.Cfg.Nodes {
		if err := m.Apply(ctx, insecure, node.Hostname); err != nil {
			var e *dagger.ExecError
			if errors.As(err, &e) && strings.Contains(e.Stderr, "certificate required") {
				if err := m.Apply(ctx, false, node.Hostname); err != nil {
					return fmt.Errorf("failed to apply config for node %s: %w", node.Hostname, err)
				}
			} else {
				return fmt.Errorf("failed to apply config for node %s: %w", node.Hostname, err)
			}
		}
	}

	return nil
}

func (m *Talos) Upgrade(
	ctx context.Context,
	node string,
	// +optional
	insecure bool,
) (*dagger.Container, error) {
	_, err := m.InstallerImage(ctx)
	if err != nil {
		return nil, err
	}
	nodeIP, err := m.Cfg.nodeIPByName(node)
	if err != nil {
		return nil, err
	}

	args := []string{"talosctl", "upgrade", "--wait", "--nodes", nodeIP}
	if insecure {
		args = append(args, "--insecure")
	}

	return m.baseContainer().WithExec(args), nil
}

// +cache="never"
func (m *Talos) Bootstrap(ctx context.Context) error {
	nodeIP, err := m.Cfg.firstControlPlaneIP()
	if err != nil {
		return err
	}

	runtimeCtr, err := m.Container(ctx)
	if err != nil {
		return fmt.Errorf("failed to create talos runtime container: %w", err)
	}

	_, err = runtimeCtr.
		WithEnvVariable("CACHEBUSTER", time.Now().String()).
		WithExec([]string{"talosctl", "bootstrap", "--nodes", nodeIP}).
		Sync(ctx)

	return err
}

func (m *Talos) KubeConfig(ctx context.Context) (*dagger.Secret, error) {
	nodeIP, err := m.Cfg.firstControlPlaneIP()
	if err != nil {
		return nil, err
	}

	runtimeCtr, err := m.Container(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to create talos runtime container: %w", err)
	}

	const kubeConfigPath = "/work/kubeconfig.yaml"
	cmd := joinShellArgs([]string{"talosctl", "kubeconfig", "--nodes", nodeIP, "--force", kubeConfigPath}) +
		" && " + joinShellArgs([]string{"cat", kubeConfigPath})

	kubeConfigContents, err := runtimeCtr.
		WithMountedTemp("/work").
		WithExec([]string{"sh", "-ec", cmd}).
		Stdout(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to generate kubeconfig: %w", err)
	}

	return dag.SetSecret("kubeconfig", kubeConfigContents), nil
}

func (m *Talos) baseContainer() *dagger.Container {
	talosctlBin := dag.Container().
		From(fmt.Sprintf("ghcr.io/siderolabs/talosctl:%s", m.Cfg.TalosVersion)).
		File("/talosctl")

	return dag.
		Wolfi().
		Container(dagger.WolfiContainerOpts{
			Packages: []string{"curl", "jq", "gettext"},
		}).
		WithFile(talosctlPath, talosctlBin, dagger.ContainerWithFileOpts{Permissions: 0o755})
}
