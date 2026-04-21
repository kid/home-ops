package main

import (
	"context"
	"dagger/bootstrap/internal/dagger"
	"errors"
	"fmt"
	"strings"
	"time"
)

type Bootstrap struct {
	Source  *dagger.Directory
	Cluster string
}

func New(
	// +defaultPath="/"
	source *dagger.Directory,
	cluster string,
) *Bootstrap {
	return &Bootstrap{
		Source:  source,
		Cluster: cluster,
	}
}

type addonSpec struct {
	kind      string
	name      string
	namespace string
	skipKinds []string
	waits     []waitSpec
}

type waitSpec struct {
	condition string
	timeout   string
	namespace string
	targets   []string
}

// +cache="never"
func (m *Bootstrap) All(
	ctx context.Context,

	talosConfigs *dagger.Directory,
	talosSecrets *dagger.Secret,
	onepasswordToken *dagger.Secret,
) error {
	talos := dag.Talos(dagger.TalosOpts{
		// Configs: m.Source.Directory(fmt.Sprintf("clusters/%s/talos", m.Cluster)),
		Configs: talosConfigs,
		Secrets: talosSecrets,
	})

	if err := talos.ApplyAll(ctx, dagger.TalosApplyAllOpts{Insecure: true}); err != nil {
		return fmt.Errorf("applying Talos configuration: %w", err)
	}

	if err := m.bootstrapTalos(ctx, talos); err != nil {
		return fmt.Errorf("bootstrapping Talos: %w", err)
	}

	kubeconfig := talos.KubeConfig()

	if err := m.WaitForTalos(ctx, kubeconfig); err != nil {
		return fmt.Errorf("waiting for nodes: %w", err)
	}

	if err := m.Crds(ctx, kubeconfig); err != nil {
		return fmt.Errorf("creating crds: %w", err)
	}

	if err := m.Namespaces(ctx, kubeconfig); err != nil {
		return fmt.Errorf("creating namespaces: %w", err)
	}

	if err := m.Apps(ctx, kubeconfig); err != nil {
		return fmt.Errorf("applying apps: %w", err)
	}

	if err := m.Secret(ctx, kubeconfig, onepasswordToken); err != nil {
		return err
	}

	if err := m.Flux(ctx, kubeconfig); err != nil {
		return err
	}

	return nil
}

func (m *Bootstrap) Container(kubeconfig *dagger.Secret) *dagger.Container {
	return dag.Wolfi().
		Container(dagger.WolfiContainerOpts{Packages: []string{"kubectl", "yq", "flux"}}).
		WithMountedSecret("/kubeconfig.yaml", kubeconfig).
		WithEnvVariable("KUBECONFIG", "/kubeconfig.yaml").
		WithDirectory("/src", m.Source).
		WithWorkdir("/src")
}

func (m *Bootstrap) bootstrapTalos(ctx context.Context, talos *dagger.Talos) error {
	const (
		maxAttempts   = 60
		retryInterval = 5 * time.Second
	)

	var lastErr error
	for attempt := 1; attempt <= maxAttempts; attempt++ {
		err := talos.Bootstrap(ctx)
		if err == nil {
			return nil
		}

		var e *dagger.ExecError
		if errors.As(err, &e) && strings.Contains(e.Stderr, "AlreadyExists") {
			return nil
		}

		lastErr = err
		if attempt == maxAttempts {
			break
		}

		select {
		case <-ctx.Done():
			return fmt.Errorf("context cancelled while waiting to retry bootstrap: %w", ctx.Err())
		case <-time.After(retryInterval):
		}
	}

	return fmt.Errorf("bootstrap failed after %d attempts: %w", maxAttempts, lastErr)
}

// +cache="never"
func (m *Bootstrap) WaitForTalos(
	ctx context.Context,
	kubeconfig *dagger.Secret,
) error {
	const apiServerReadyScript = `
attempt=0
max_attempts=30

until kubectl --request-timeout=5s get --raw=/readyz >/dev/null 2>&1; do
	attempt=$((attempt + 1))
	if [ "$attempt" -ge "$max_attempts" ]; then
		exit 1
	fi
	sleep 5
done
`

	if _, err := m.Container(kubeconfig).
		WithExec([]string{"sh", "-ec", apiServerReadyScript}).
		Sync(ctx); err != nil {
		return fmt.Errorf("waiting for Kubernetes API server availability: %w", err)
	}

	waitReadyTrueErr := m.Wait(ctx, kubeconfig, "Ready=true", "10s", "", []string{"nodes", "--all"})
	if waitReadyTrueErr == nil {
		return nil
	}

	waitReadyFalseErr := m.Wait(ctx, kubeconfig, "Ready=false", "1m", "", []string{"nodes", "--all"})
	if waitReadyFalseErr == nil {
		return nil
	}

	return fmt.Errorf("waiting for nodes Ready=true failed, and fallback Ready=false also failed: %w", errors.Join(waitReadyTrueErr, waitReadyFalseErr))
}

// +cache="never"
func (m *Bootstrap) Wait(
	ctx context.Context,
	kubeconfig *dagger.Secret,
	condition string,
	timeout string,
	// +optional
	namespace string,
	targets []string,
) error {
	args := []string{"kubectl", "wait", fmt.Sprintf("--for=condition=%s", condition), fmt.Sprintf("--timeout=%s", timeout)}
	if namespace != "" {
		args = append(args, "--namespace", namespace)
	}
	args = append(args, targets...)

	_, err := m.Container(kubeconfig).WithExec(args).Sync(ctx)
	if err != nil {
		return fmt.Errorf("kubectl wait for %s on %s: %w", condition, strings.Join(targets, ", "), err)
	}

	return nil
}

// +cache="never"
func (m *Bootstrap) Namespaces(
	ctx context.Context,
	kubeconfig *dagger.Secret,
) error {
	path := fmt.Sprintf("clusters/%s", m.Cluster)
	manifests := dag.
		FluxLocal(dagger.FluxLocalOpts{Source: m.Source}).
		Build(path, dagger.FluxLocalBuildOpts{
			Kind: "all",
			// EnvFile: m.Source.File(fmt.Sprintf("clusters/%s/%s.env", m.Cluster, m.Cluster)),
		})
	_, err := m.Container(kubeconfig).
		WithFile("/manifests.yaml", manifests).
		WithExec([]string{
			"sh", "-ec", "yq -e 'select(.kind == \"Namespace\")' /manifests.yaml | kubectl apply --server-side --field-manager=bootstrap --force-conflicts -f -",
		}).Sync(ctx)
	return err
}

// +cache="never"
func (m *Bootstrap) Crds(
	ctx context.Context,
	kubeconfig *dagger.Secret,
) error {
	path := fmt.Sprintf("clusters/%s", m.Cluster)
	manifests := dag.
		FluxLocal(dagger.FluxLocalOpts{Source: m.Source}).
		Build(path, dagger.FluxLocalBuildOpts{
			Kind: "all",
			// EnvFile: m.Source.File(fmt.Sprintf("clusters/%s/cluster.env", m.Cluster)),
		})
	_, err := m.Container(kubeconfig).
		WithFile("/manifests.yaml", manifests).
		WithExec([]string{
			"sh", "-ec", "yq -e 'select(.kind == \"CustomResourceDefinition\")' /manifests.yaml | kubectl apply --server-side --field-manager=bootstrap --force-conflicts -f -",
		}).Sync(ctx)
	return err
}

func (m *Bootstrap) Apps(
	ctx context.Context,
	kubeconfig *dagger.Secret,
) error {
	releases := []addonSpec{
		{
			kind:      "hr",
			name:      "cilium",
			namespace: "kube-system",
			skipKinds: []string{"ServiceMonitor"},
			waits: []waitSpec{
				{
					condition: "Available",
					timeout:   "5m",
					namespace: "kube-system",
					targets: []string{
						"deployment/cilium-operator",
					},
				},
			},
		},
		{
			kind:      "ks",
			name:      "cilium-resources",
			namespace: "kube-system",
		},
		{
			kind:      "hr",
			name:      "external-secrets",
			namespace: "external-secrets",
			skipKinds: []string{"ServiceMonitor"},
			waits: []waitSpec{
				{
					condition: "Established",
					timeout:   "5m",
					targets: []string{
						"crd/externalsecrets.external-secrets.io",
						"crd/clustersecretstores.external-secrets.io",
					},
				},
			},
		},
		{
			kind:      "hr",
			name:      "flux-operator",
			namespace: "flux-system",
			skipKinds: []string{"ServiceMonitor"},
			waits: []waitSpec{
				{
					condition: "Established",
					timeout:   "5m",
					targets: []string{
						"crd/fluxinstances.fluxcd.controlplane.io",
						"crd/fluxreports.fluxcd.controlplane.io",
						"crd/resourcesetinputproviders.fluxcd.controlplane.io",
						"crd/resourcesets.fluxcd.controlplane.io",
					},
				},
			},
		},
		{
			kind:      "hr",
			name:      "flux-instance",
			namespace: "flux-system",
			waits: []waitSpec{
				{
					condition: "Ready",
					timeout:   "5m",
					namespace: "flux-system",
					targets:   []string{"fluxinstance.fluxcd.controlplane.io/flux"},
				},
			},
		},
	}

	for _, release := range releases {
		err := m.Apply(ctx, kubeconfig, release.kind, release.name, release.namespace, release.skipKinds)
		if err != nil {
			return err
		}

		for _, wait := range release.waits {
			err = m.Wait(ctx, kubeconfig, wait.condition, wait.timeout, wait.namespace, wait.targets)
			if err != nil {
				return fmt.Errorf("waiting for %s/%s: %w", release.namespace, release.name, err)
			}
		}
	}

	return nil
}

// +cache="never"
func (m *Bootstrap) Apply(
	ctx context.Context,
	kubeconfig *dagger.Secret,
	kind string,
	name string,
	// +default="flux-system"
	namespace string,
	// +optional
	skipKinds []string,
) error {
	path := fmt.Sprintf("clusters/%s", m.Cluster)
	manifest := dag.
		FluxLocal(dagger.FluxLocalOpts{Source: m.Source}).
		Build(path, dagger.FluxLocalBuildOpts{
			Kind:      kind,
			Name:      name,
			Namespace: namespace,
			SkipKinds: skipKinds,
			// EnvFile:   m.Source.File(fmt.Sprintf("clusters/%s/cluster.env", m.Cluster)),
		})

	ctr := m.Container(kubeconfig).
		WithMountedFile("/manifests.yaml", manifest).
		WithEnvFileVariables(m.Source.File(fmt.Sprintf("clusters/%s/cluster.env", m.Cluster)).AsEnvFile()).
		WithExec([]string{"/bin/sh", "-ec", "cat /manifests.yaml | flux envsubst | kubectl apply --server-side --field-manager=bootstrap --force-conflicts -f -"})

	_, err := ctr.Sync(ctx)
	if err != nil {
		return fmt.Errorf("applying Flux resource %s/%s: %w", namespace, name, err)
	}

	return nil
}

func (m *Bootstrap) Secret(
	ctx context.Context,
	kubeconfig *dagger.Secret,
	onepasswordToken *dagger.Secret,
) error {
	_, err := m.Container(kubeconfig).
		// WithSecretVariable("OP_SERVICE_ACCOUNT_TOKEN", onepasswordToken).
		WithMountedSecret("/secrets.env", onepasswordToken).
		WithExec([]string{"kubectl", "create", "secret", "generic", "onepassword-secret", "-n", "external-secrets", "--from-file=token=/secrets.env"}).
		Sync(ctx)
	if err != nil {
		return fmt.Errorf("creating onepassword secret: %w", err)
	}

	return nil
}

func (m *Bootstrap) Flux(
	ctx context.Context,
	kubeconfig *dagger.Secret,
) error {

	_, err := m.Container(kubeconfig).WithExec([]string{"kubectl", "apply", "-k", fmt.Sprintf("clusters/%s", m.Cluster)}).Sync(ctx)
	if err != nil {
		return fmt.Errorf("applying Flux configuration: %w", err)
	}

	return nil
}
