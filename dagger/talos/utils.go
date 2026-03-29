package main

import (
	"fmt"
	"strings"
)

func machineConfigSecretName(nodeName string) string {
	name := sanitizeSecretNamePart(nodeName)
	if name == "" {
		return "machineconfig-default"
	}

	return "machineconfig-" + name
}

func sanitizeSecretNamePart(s string) string {
	s = strings.TrimSpace(strings.ToLower(s))
	if s == "" {
		return ""
	}

	replacer := strings.NewReplacer("/", "-", "\\", "-", ":", "-", " ", "-", "_", "-")
	s = replacer.Replace(s)
	s = strings.Trim(s, "-")
	return s
}

func buildTalosConfigScript(cfg *talosConfig, endpoints []string, nodes []string) string {
	const talosconfigPath = "/work/talosconfig.yaml"

	cmds := []string{
		fmt.Sprintf(
			"talosctl gen config %s %s --output-types=talosconfig --output=%s --with-secrets=/secrets.yaml",
			shellQuote(cfg.ClusterName),
			shellQuote(cfg.ClusterEndpoint),
			shellQuote(talosconfigPath),
		),
	}

	if len(endpoints) > 0 {
		args := []string{"talosctl", "config", "--talosconfig", talosconfigPath, "--context", cfg.ClusterName, "endpoints"}
		args = append(args, endpoints...)
		cmds = append(cmds, joinShellArgs(args))
	}

	if len(nodes) > 0 {
		args := []string{"talosctl", "config", "--talosconfig", talosconfigPath, "--context", cfg.ClusterName, "nodes"}
		args = append(args, nodes...)
		cmds = append(cmds, joinShellArgs(args))
	}

	cmds = append(cmds, fmt.Sprintf("cat %s", shellQuote(talosconfigPath)))
	return strings.Join(cmds, " && ")
}

func joinShellArgs(args []string) string {
	quoted := make([]string, 0, len(args))
	for _, arg := range args {
		quoted = append(quoted, shellQuote(arg))
	}

	return strings.Join(quoted, " ")
}

func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", "'\"'\"'") + "'"
}
