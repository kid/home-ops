package main

import (
	"context"
	"dagger/flux-local/internal/dagger"
	"fmt"
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
) (*dagger.File, error) {
	args := []string{"flux-local", "build", kind, "--output", "/out/manifests.yaml", "--no-skip-crds", "--no-skip-secrets"}
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

	ctr, err := m.Container().WithExec(args).Sync(ctx)
	if err != nil {
		return nil, err
	}

	return ctr.File("/out/manifests.yaml"), nil
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
		out, err := ctr.WithExec([]string{"flux-local", "build", "all", "--enable-helm", fmt.Sprintf("clusters/%s", cluster)}).CombinedOutput(ctx)
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
