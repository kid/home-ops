package main

import (
	"context"
	"dagger/flux-local/internal/dagger"
	"fmt"
	"path/filepath"
	"strings"
)

type FluxLocal struct {
	Source  *dagger.Directory
	Version string

	ctr *dagger.Container
}

func New(
	// +defaultPath="/"
	source *dagger.Directory,
	// +default="v8.1.0"
	version string,
) *FluxLocal {
	return &FluxLocal{
		Source:  source,
		Version: version,
	}
}

func (m *FluxLocal) Container() *dagger.Container {
	if m.ctr == nil {
		m.ctr = dag.
			Container().
			From(fmt.Sprintf("ghcr.io/allenporter/flux-local:%s", m.Version)).
			WithDirectory("/out", dag.Directory(), dagger.ContainerWithDirectoryOpts{Owner: "1001"}).
			WithDirectory("/src", m.Source, dagger.ContainerWithDirectoryOpts{Owner: "1001"}).
			WithWorkdir("/src")
	}

	return m.ctr
}

func (m *FluxLocal) Get(
	ctx context.Context,
	// +default="ks"
	kind string,
	// +optional
	path string,
) (string, error) {
	args := []string{"flux-local", "get", kind, "-A"}
	if path != "" {
		args = append(args, "--path", path)
	}

	return m.Container().WithExec(args).Stdout(ctx)
}

func (m *FluxLocal) Build(
	ctx context.Context,
	path string,
	// +default="hr"
	kind string,
	// +optional
	name string,
	// +optional
	namespace string,
	// +optional
	skipKinds []string,
	// +optional
	skipHelm bool,
	// +optional
	envFile *dagger.File,
) (*dagger.File, error) {
	// flux-local understands Flux postBuild substitution, but only when the
	// referenced ConfigMap exists in the repo it is traversing. When bootstrap
	// provides cluster.env, inject a concrete cluster-values ConfigMap into the
	// temporary source tree instead of running a blind envsubst pass over the
	// rendered output, which would also rewrite Helm/runtime placeholders.
	source := m.Source
	if envFile != nil {
		var err error
		source, err = m.withClusterValues(ctx, path, envFile)
		if err != nil {
			return nil, err
		}
	}

	// FIXME: skipping invalid paths because of kubevirt source
	args := []string{"flux-local", "build", kind, "--output", "/out/manifests.yaml", "--no-skip-crds", "--no-skip-secrets", "--skip-invalid-kustomization-paths"}
	if len(skipKinds) > 0 {
		args = append(args, "--skip-kinds", strings.Join(skipKinds, ","))
	}

	if kind == "all" {
		if !skipHelm {
			args = append(args, "--enable-helm")
		}
		args = append(args, path)
	} else {
		if namespace != "" {
			args = append(args, "--namespace", namespace)
		} else {
			args = append(args, "-A")
		}
		args = append(args, "--path", path, name)
	}

	ctr, err := dag.
		Container().
		From(fmt.Sprintf("ghcr.io/allenporter/flux-local:%s", m.Version)).
		WithDirectory("/out", dag.Directory(), dagger.ContainerWithDirectoryOpts{Owner: "1001"}).
		WithDirectory("/src", source, dagger.ContainerWithDirectoryOpts{Owner: "1001"}).
		WithWorkdir("/src").
		WithExec(args).
		Sync(ctx)
	if err != nil {
		return nil, err
	}

	return ctr.File("/out/manifests.yaml"), nil
}

// withClusterValues injects a concrete cluster-values ConfigMap into the build
// tree so flux-local can resolve postBuild.substituteFrom locally from
// cluster.env. This keeps substitution scoped to Flux inputs and avoids
// clobbering placeholders that must survive into Helm-rendered manifests.
func (m *FluxLocal) withClusterValues(
	ctx context.Context,
	path string,
	envFile *dagger.File,
) (*dagger.Directory, error) {
	envContents, err := envFile.Contents(ctx)
	if err != nil {
		return nil, fmt.Errorf("reading env file: %w", err)
	}

	clusterValuesComponentPath := filepath.Join("kubernetes", "components", "cluster-values", "cluster-values.yaml")
	clusterValuesComponent := buildClusterValuesConfigMap(envContents, "")

	clusterValuesManifestPath := filepath.Join(path, "cluster-values.generated.yaml")
	clusterValuesManifest := buildClusterValuesConfigMap(envContents, "flux-system")

	topLevelKustomizationPath := filepath.Join(path, "kustomization.yaml")
	topLevelKustomization := strings.Join([]string{
		"---",
		"apiVersion: kustomize.config.k8s.io/v1beta1",
		"kind: Kustomization",
		"resources:",
		"  - ./flux",
		"  - ./cluster-values.generated.yaml",
		"",
	}, "\n")

	return m.Source.
		WithNewFile(clusterValuesComponentPath, clusterValuesComponent).
		WithNewFile(clusterValuesManifestPath, clusterValuesManifest).
		WithNewFile(topLevelKustomizationPath, topLevelKustomization), nil
}

// buildClusterValuesConfigMap converts a simple env file into the ConfigMap
// shape expected by postBuild.substituteFrom consumers.
func buildClusterValuesConfigMap(envContents string, namespace string) string {
	lines := []string{
		"---",
		"apiVersion: v1",
		"kind: ConfigMap",
		"metadata:",
		"  name: cluster-values",
	}
	if namespace != "" {
		lines = append(lines, fmt.Sprintf("  namespace: %s", namespace))
	}
	lines = append(lines, "data:")

	for _, line := range strings.Split(envContents, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		key, value, ok := strings.Cut(line, "=")
		if !ok || key == "" {
			continue
		}

		lines = append(lines, fmt.Sprintf("  %s: %q", key, value))
	}

	return strings.Join(lines, "\n") + "\n"
}

// +check
func (m *FluxLocal) Diagnostics(
	ctx context.Context,
) error {
	_, err := m.Container().WithExec([]string{"flux-local", "diagnostics"}).Sync(ctx)
	return err
}

// +check
func (m *FluxLocal) Test(
	ctx context.Context,
) (string, error) {
	var err error
	clusters, err := m.Source.Entries(ctx, dagger.DirectoryEntriesOpts{Path: "clusters"})
	if err != nil {
		return "", err
	}

	var results []string
	ctr := m.Container()
	for _, cluster := range clusters {
		out, err := ctr.WithExec([]string{"flux-local", "test", "-A", "--enable-helm", "--path", fmt.Sprintf("clusters/%s", cluster)}).CombinedOutput(ctx)
		if err != nil {
			return "", fmt.Errorf("tests failed for cluster %s: %w\nOutput:\n%s", cluster, err, out)
		}
		results = append(results, out)
	}

	return strings.Join(results, "\n"), nil
}

// +check
func (m *FluxLocal) TestBuild(
	ctx context.Context,
) (string, error) {
	var err error
	clusters, err := m.Source.Entries(ctx, dagger.DirectoryEntriesOpts{Path: "clusters"})
	if err != nil {
		return "", err
	}

	var results []string
	ctr := m.Container()
	for _, cluster := range clusters {
		out, err := ctr.WithExec([]string{"flux-local", "build", "all", "--skip-invalid-kustomization-paths", "--enable-helm", fmt.Sprintf("clusters/%s", cluster)}).CombinedOutput(ctx)
		if err != nil {
			return "", fmt.Errorf("tests failed for cluster %s: %w\nOutput:\n%s", cluster, err, out)
		}
		results = append(results, out)
	}

	return strings.Join(results, "\n"), nil
}

func (m *FluxLocal) Diff(
	ctx context.Context,
	path string,
	// +default="ks"
	kind string,
	// +optional
	namespace string,
	// +optional
	// +default="main"
	branch string,
) (*dagger.Container, error) {
	args := []string{"flux-local", "diff", kind, "--path", path}
	if namespace != "" {
		args = append(args, "--namespace", namespace)
	} else {
		args = append(args, "-A")
	}

	if branch != "" {
		args = append(args, "--branch-orig", branch)
	}

	return m.Container().WithExec(args).Sync(ctx)
}
