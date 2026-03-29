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
	Secrets *dagger.Secret
}

func New(
	// +optional
	configs *dagger.Directory,
	// +optional
	secrets *dagger.Secret,
) *Talos {
	return &Talos{
		Configs: configs,
		Secrets: secrets,
	}
}

func (m *Talos) MachineConfig(
	ctx context.Context,
	// +optional
	nodeName string,
) (*dagger.Secret, error) {
	cfg, err := m.loadConfig(ctx)
	if err != nil {
		return nil, err
	}

	nodeType, err := cfg.nodeType(nodeName)
	if err != nil {
		return nil, err
	}

	args := []string{
		"talosctl", "gen", "config", cfg.ClusterName, cfg.ClusterEndpoint,
		fmt.Sprintf("--output-types=%s", nodeType), "--output=-",
		"--with-secrets=/secrets.yaml",
		"--with-docs=false",
		"--with-examples=false",
		"--with-kubespan=false",
	}

	patches, err := cfg.patchesFor(nodeName)
	if err != nil {
		return nil, err
	}

	for _, patchPath := range patches {
		args = append(args, fmt.Sprintf("--config-patch=@/src/%s", patchPath))
	}

	ctr := m.baseContainer(cfg).
		WithMountedSecret("/secrets.yaml", m.Secrets).
		WithDirectory("/src", m.Configs).
		WithExec(args)

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

	cfg, err := m.loadConfig(ctx)
	if err != nil {
		return err
	}

	for _, n := range cfg.Nodes {
		if node != "" && n.Hostname != node {
			continue
		}

		machineCfg, err := m.MachineConfig(ctx, n.Hostname)
		if err != nil {
			return fmt.Errorf("failed to generate machine config for validation: %w", err)
		}

		_, err = m.baseContainer(cfg).
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
	cfg, err := m.loadConfig(ctx)
	if err != nil {
		return nil, err
	}

	endpoints := cfg.controlPlaneIPs()
	nodes := cfg.nodeIPs()
	script := buildTalosConfigScript(cfg, endpoints, nodes)

	ctr := m.baseContainer(cfg).
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
	cfg, err := m.loadConfig(ctx)
	if err != nil {
		return nil, err
	}

	talosCfg, err := m.TalosConfig(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to generate talos config for runtime container: %w", err)
	}

	return m.baseContainer(cfg).
		WithMountedSecret("/talosconfig.yaml", talosCfg).
		WithEnvVariable("TALOSCONFIG", "/talosconfig.yaml").
		WithEnvVariable("TERM", "xterm-256color").
		Sync(ctx)
}

func (m *Talos) Dashboard(ctx context.Context) (*dagger.Container, error) {
	ctr, err := m.Container(ctx)
	if err != nil {
		return nil, err
	}

	return ctr.WithExec([]string{"talosctl", "dashboard"}), nil
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

	cfg, err := m.loadConfig(ctx)
	if err != nil {
		return err
	}

	nodeIP, err := cfg.nodeIPByName(node)
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
	cfg, err := m.loadConfig(ctx)
	if err != nil {
		return err
	}

	for _, node := range cfg.Nodes {
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

// +cache="never"
func (m *Talos) Bootstrap(ctx context.Context) error {
	cfg, err := m.loadConfig(ctx)
	if err != nil {
		return err
	}

	nodeIP, err := cfg.firstControlPlaneIP()
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
	cfg, err := m.loadConfig(ctx)
	if err != nil {
		return nil, err
	}

	nodeIP, err := cfg.firstControlPlaneIP()
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

func (m *Talos) baseContainer(cfg *talosConfig) *dagger.Container {
	talosctlBin := dag.Container().
		From(fmt.Sprintf("ghcr.io/siderolabs/talosctl:%s", cfg.TalosVersion)).
		File("/talosctl")

	return dag.Wolfi().Container().
		WithFile(talosctlPath, talosctlBin, dagger.ContainerWithFileOpts{Permissions: 0o755})
}
