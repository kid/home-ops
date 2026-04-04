package main

import (
	"context"
	"dagger/talos/internal/dagger"
	"fmt"
	"path"
	"strings"

	"gopkg.in/yaml.v3"
)

type TalosConfig struct {
	ClusterName         string
	ClusterEndpoint     string
	Target              string
	TalosVersion        string
	ControlPlanePatches []string
	Nodes               []TalosNode
}

type TalosNode struct {
	IPAddress string
	Hostname  string
	Role      string
	Patches   []string
}

type TalosConfigFile struct {
	ClusterName  string `yaml:"clusterName"`
	Endpoint     string `yaml:"endpoint"`
	TalosVersion string `yaml:"talosVersion"`
	Target       string `yaml:"target"`
	Nodes        []struct {
		IPAddress string   `yaml:"ipAddress"`
		Hostname  string   `yaml:"hostname"`
		Role      string   `yaml:"role"`
		Patches   []string `yaml:"patches"`
	} `yaml:"nodes"`
	Patches struct {
		ControlPlane []string `yaml:"controlplane"`
	} `yaml:"patches"`
}

func loadConfig(ctx context.Context, configs *dagger.Directory) (*TalosConfig, error) {
	const configPath = "config.yaml"

	contents, err := configs.File(configPath).Contents(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to read talos config file %q: %w", configPath, err)
	}

	var cfgFile TalosConfigFile
	if err := yaml.Unmarshal([]byte(contents), &cfgFile); err != nil {
		return nil, fmt.Errorf("failed to parse talos config file %q: %w", configPath, err)
	}

	if cfgFile.ClusterName == "" {
		return nil, fmt.Errorf("invalid talos config file %q: clusterName is required", configPath)
	}

	if cfgFile.Endpoint == "" {
		return nil, fmt.Errorf("invalid talos config file %q: endpoint is required", configPath)
	}

	if strings.TrimSpace(cfgFile.Target) == "" {
		return nil, fmt.Errorf("invalid talos config file %q: target is required", configPath)
	}

	controlPlanePatches, err := resolvePatches(path.Dir(configPath), cfgFile.Patches.ControlPlane)
	if err != nil {
		return nil, fmt.Errorf("invalid control-plane patches in %q: %w", configPath, err)
	}

	nodes := make([]TalosNode, 0, len(cfgFile.Nodes))
	for _, node := range cfgFile.Nodes {
		if node.IPAddress == "" {
			if node.Hostname != "" {
				return nil, fmt.Errorf("invalid talos config file %q: ipAddress is required for node %q", configPath, node.Hostname)
			}

			return nil, fmt.Errorf("invalid talos config file %q: ipAddress is required for all nodes", configPath)
		}

		nodePatches, err := resolvePatches(path.Dir(configPath), node.Patches)
		if err != nil {
			return nil, fmt.Errorf("invalid patches for node %q in %q: %w", node.Hostname, configPath, err)
		}

		nodes = append(nodes, TalosNode{
			IPAddress: node.IPAddress,
			Hostname:  node.Hostname,
			Role:      node.Role,
			Patches:   nodePatches,
		})
	}

	talosVersion := cfgFile.TalosVersion
	if talosVersion == "" {
		talosVersion = "v1.12.6"
	}

	return &TalosConfig{
		ClusterName:         cfgFile.ClusterName,
		ClusterEndpoint:     cfgFile.Endpoint,
		Target:              strings.TrimSpace(cfgFile.Target),
		TalosVersion:        talosVersion,
		ControlPlanePatches: controlPlanePatches,
		Nodes:               nodes,
	}, nil
}

func (c *TalosConfig) patchesFor(nodeName string) ([]string, error) {
	nodeType, err := c.nodeType(nodeName)
	if err != nil {
		return nil, err
	}

	patches := make([]string, 0, len(c.ControlPlanePatches))

	if nodeType == "controlplane" {
		patches = append(patches, c.ControlPlanePatches...)
	}

	if nodeName == "" {
		return patches, nil
	}

	node, ok := c.nodeByName(nodeName)
	if !ok {
		return nil, fmt.Errorf("node %q not found in config.yaml", nodeName)
	}

	patches = append(patches, node.Patches...)
	return patches, nil
}

func (c *TalosConfig) nodeType(nodeName string) (string, error) {
	if nodeName == "" {
		return "controlplane", nil
	}

	node, ok := c.nodeByName(nodeName)
	if !ok {
		return "", fmt.Errorf("node %q not found in config.yaml", nodeName)
	}

	role := strings.ToLower(strings.TrimSpace(node.Role))
	switch role {
	case "controlplane":
		return "controlplane", nil
	case "worker":
		return "worker", nil
	default:
		return "", fmt.Errorf("unsupported role %q for node %q (expected controlplane or worker)", node.Role, nodeName)
	}
}

func (c *TalosConfig) nodeByName(name string) (TalosNode, bool) {
	for _, node := range c.Nodes {
		if node.Hostname == name {
			return node, true
		}
	}

	return TalosNode{}, false
}

func (c *TalosConfig) nodeIPByName(name string) (string, error) {
	node, ok := c.nodeByName(name)
	if !ok {
		return "", fmt.Errorf("node %q not found in config.yaml", name)
	}

	if strings.TrimSpace(node.IPAddress) == "" {
		return "", fmt.Errorf("node %q has no ipAddress in config.yaml", name)
	}

	return node.IPAddress, nil
}

func (c *TalosConfig) nodeIPs() []string {
	ips := make([]string, 0, len(c.Nodes))
	for _, node := range c.Nodes {
		if node.IPAddress == "" {
			continue
		}

		ips = append(ips, node.IPAddress)
	}

	return ips
}

func (c *TalosConfig) controlPlaneIPs() []string {
	ips := make([]string, 0, len(c.Nodes))
	for _, node := range c.Nodes {
		if node.IPAddress == "" {
			continue
		}

		role := strings.ToLower(strings.TrimSpace(node.Role))
		if role != "controlplane" {
			continue
		}

		ips = append(ips, node.IPAddress)
	}

	return ips
}

func (c *TalosConfig) firstControlPlaneIP() (string, error) {
	for _, node := range c.Nodes {
		if strings.TrimSpace(node.IPAddress) == "" {
			continue
		}

		role := strings.ToLower(strings.TrimSpace(node.Role))
		if role != "controlplane" {
			continue
		}

		return node.IPAddress, nil
	}

	return "", fmt.Errorf("no controlplane node with an ipAddress found in config.yaml")
}

func resolvePatches(configDir string, patchPaths []string) ([]string, error) {
	resolved := make([]string, 0, len(patchPaths))
	for _, patchPath := range patchPaths {
		patchPath = strings.TrimSpace(patchPath)
		if patchPath == "" {
			return nil, fmt.Errorf("patch path cannot be empty")
		}

		if path.IsAbs(patchPath) {
			return nil, fmt.Errorf("patch path %q must be relative", patchPath)
		}

		resolvedPath := path.Clean(path.Join(configDir, patchPath))
		if resolvedPath == ".." || strings.HasPrefix(resolvedPath, "../") {
			return nil, fmt.Errorf("patch path %q escapes config directory", patchPath)
		}

		resolved = append(resolved, resolvedPath)
	}

	return resolved, nil
}
