package test

import (
	"testing"

	"github.com/getsops/sops/v3/decrypt"
	"github.com/gruntwork-io/terratest/modules/ssh"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	yaml "gopkg.in/yaml.v3"
)

type RouterosUser struct {
	Password string `yaml:"password"`
}

type RouterosSecrets struct {
	Username string                  `yaml:"routeros_username"`
	Users    map[string]RouterosUser `yaml:"users"`
}

func TestSsh(t *testing.T) {
	t.Parallel()

	plaintext, err := decrypt.File("../secrets/dev/routeros.sops.yaml", "yaml")
	if err != nil {
		t.Fatalf("failed to decode secret file: %v", err)
	}

	var secrets RouterosSecrets
	if err := yaml.Unmarshal(plaintext, &secrets); err != nil {
		t.Fatalf("failed to parsed decrypted secrets: %v", err)
	}

	ssh_username := secrets.Username
	ssh_password := secrets.Users[ssh_username].Password

	// FIXME: need a fix from terratest...
	// terraformLab := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
	// 	TerraformDir:    "../tf-stacks/dev/lab",
	// 	TerraformBinary: "terragrunt",
	// })
	// oob_ips := terraform.OutputMap(t, terraformLab, "oob_ips")
	oob_ips := map[string]string{
		"router":   "192.168.89.2",
		"switch":   "192.168.89.3",
		"trusted1": "192.168.89.4",
		"trusted2": "192.168.89.6",
		"guest1":   "192.168.89.5",
		"guest2":   "192.168.89.7",
	}

	mkHost := func(hostname string) ssh.Host {
		return ssh.Host{
			Hostname:    oob_ips[hostname],
			SshUserName: ssh_username,
			Password:    ssh_password,
		}
	}

	test_structure.RunTestStage(t, "setup", func() {
		router := mkHost("router")

		// Cleanup connection tracking on the router
		RunSshCommand(t, router, "/ip/firewall/connection/remove [find]")
	})

	test_structure.RunTestStage(t, "validate", func() {
		t.Run("trusted1", makeTrustedNetworkTest(mkHost("trusted1")))
		t.Run("trusted2", makeTrustedNetworkTest(mkHost("trusted2")))
		t.Run("guest1", makeGuestNetworkTest(mkHost("guest1")))
		t.Run("guest2", makeGuestNetworkTest(mkHost("guest2")))
	})
}

func makeTrustedNetworkTest(host ssh.Host) func(*testing.T) {
	return func(t *testing.T) {
		type checkFunc func(t *testing.T) error
		tc := [...]struct {
			name  string
			check func(t *testing.T)
		}{
			{
				name:  "Can ping the router on the trusted network",
				check: func(t *testing.T) { CanPing(t, host, "10.128.100.1") },
			},
			{
				name:  "Can ping the router on the management network",
				check: func(t *testing.T) { CanPing(t, host, "10.227.0.1") },
			},
			{
				name:  "Can ping access the internet",
				check: func(t *testing.T) { CanPing(t, host, "1.1.1.1") },
			},
			{
				name:  "Can resolve on the internet",
				check: func(t *testing.T) { CanPing(t, host, "google.com") },
			},
		}

		for _, tt := range tc {
			t.Run(tt.name, func(t *testing.T) {
				tt.check(t)
			})
		}
	}
}

func makeGuestNetworkTest(host ssh.Host) func(*testing.T) {
	return func(t *testing.T) {
		type checkFunc func(t *testing.T) error
		tc := [...]struct {
			name  string
			check func(t *testing.T)
		}{
			{
				name:  "Can ping the router on the guest network",
				check: func(t *testing.T) { CanPing(t, host, "10.128.110.1") },
			},
			{
				name:  "Can not ping the router on the management network",
				check: func(t *testing.T) { CanNotPing(t, host, "10.227.0.1") },
			},
			{
				name:  "Can ping access the internet",
				check: func(t *testing.T) { CanPing(t, host, "1.1.1.1") },
			},
			{
				name:  "Can resolve on the internet",
				check: func(t *testing.T) { CanPing(t, host, "google.com") },
			}}

		for _, tt := range tc {
			t.Run(tt.name, func(t *testing.T) {
				tt.check(t)
			})
		}
	}
}
