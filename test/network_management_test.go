package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/ssh"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
)

func TestSsh(t *testing.T) {
	t.Parallel()

	// terraformLab := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
	// 	TerraformDir:    "../tf-stacks/dev/lab",
	// 	TerraformBinary: "terragrunt",
	// })
	// oob_ips := terraform.OutputMap(t, terraformLab, "oob_ips")
	oob_ips := map[string]string{
		"guest1":   "192.168.89.5",
		"guest2":   "192.168.89.7",
		"router":   "192.168.89.2",
		"switch":   "192.168.89.3",
		"trusted1": "192.168.89.4",
		"trusted2": "192.168.89.6",
	}

	test_structure.RunTestStage(t, "setup", func() {
		router := ssh.Host{
			Hostname:    oob_ips["router"],
			SshUserName: "admin",
			Password:    "admin",
		}

		// Cleanup connection tracking on the router
		RunSshCommand(t, router, "/ip/firewall/connection/remove [find]")
	})

	test_structure.RunTestStage(t, "validate", func() {
		t.Run("trusted1", makeTrustedNetworkTest(oob_ips["trusted1"]))
		t.Run("trusted2", makeTrustedNetworkTest(oob_ips["trusted2"]))
		t.Run("guest1", makeGuestNetworkTest(oob_ips["guest1"]))
		t.Run("guest2", makeGuestNetworkTest(oob_ips["guest2"]))
	})
}

func makeTrustedNetworkTest(hostname string) func(*testing.T) {
	return func(t *testing.T) {
		host := ssh.Host{
			Hostname:    hostname,
			SshUserName: "admin",
			Password:    "admin",
		}

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
			}}

		for _, tt := range tc {
			t.Run(tt.name, func(t *testing.T) {
				tt.check(t)
			})
		}
	}
}

func makeGuestNetworkTest(hostname string) func(*testing.T) {
	return func(t *testing.T) {
		host := ssh.Host{
			Hostname:    hostname,
			SshUserName: "admin",
			Password:    "admin",
		}

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
