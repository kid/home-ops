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

func (m *FluxLocal) Container(ctx context.Context) (*dagger.Container, error) {
	ctr := dag.Container().From(fmt.Sprintf("ghcr.io/allenporter/flux-local:%s", m.Version))
	user, err := ctr.User(ctx)
	if err != nil {
		return nil, err
	}

	return ctr.
		WithDirectory("/out", dag.Directory(), dagger.ContainerWithDirectoryOpts{Owner: user}).
		WithDirectory("/src", m.Source, dagger.ContainerWithDirectoryOpts{Owner: user}).
		WithWorkdir("/src"), nil
}

func (m *FluxLocal) Get(
	ctx context.Context,
	// +default="ks"
	kind string,
	// +optional
	path string,
) (string, error) {
	ctr, err := m.Container(ctx)
	if err != nil {
		return "", err
	}

	args := []string{"flux-local", "get", kind, "-A"}
	if path != "" {
		args = append(args, "--path", path)
	}

	return ctr.WithExec(args).Stdout(ctx)
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
	ctr, err := m.Container(ctx)
	if err != nil {
		return nil, err
	}

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

	ctr, err = ctr.WithExec(args).Sync(ctx)
	if err != nil {
		return nil, err
	}

	return ctr.File("/out/manifests.yaml"), nil
}

// +check
func (m *FluxLocal) Test(
	ctx context.Context,
) (*dagger.Container, error) {
	var err error
	clusters, err := m.Source.Entries(ctx, dagger.DirectoryEntriesOpts{Path: "clusters"})
	if err != nil {
		return nil, err
	}

	ctr, err := m.Container(ctx)
	if err != nil {
		return nil, err
	}

	for _, cluster := range clusters {
		ctr = ctr.WithExec([]string{"flux-local", "test", "-A", "--enable-helm", "--path", fmt.Sprintf("clusters/%s", cluster)})
	}

	return ctr.Sync(ctx)
}
