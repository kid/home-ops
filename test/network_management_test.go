package test

import (
	"crypto/tls"
	"fmt"
	"strings"
	"testing"

	"github.com/getsops/sops/v3/decrypt"
	"github.com/go-routeros/routeros/v3"
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

func rosClient(address, username, password string) (*routeros.Client, error) {
	return routeros.DialTLS(fmt.Sprintf("%s:8729", address), username, password, &tls.Config{
		InsecureSkipVerify: true,
	})
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

	ros_username := secrets.Username
	ros_password := secrets.Users[ros_username].Password

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
			SshUserName: ros_username,
			Password:    ros_password,
		}
	}

	lease_ips := make(map[string]string)

	test_structure.RunTestStage(t, "setup", func() {
		router := mkHost("router")

		// Cleanup connection tracking on the router
		RunSshCommand(t, router, "/ip/firewall/connection/remove [find]")
		client, err := rosClient(oob_ips["router"], ros_username, ros_password)
		if err != nil {
			t.Fatalf("failed to connect to routeros: %v", err)
		}

		var reply *routeros.Reply
		if reply, err = client.Run("/ip/dhcp-server/lease/print"); err != nil {
			t.Fatalf("failed to get DHCP leases: %v", err)
		}

		t.Logf("Current DHCP leases:")
		for _, re := range reply.Re {
			lease_ips[re.Map["host-name"]] = re.Map["active-address"]
		}
	})

	test_structure.RunTestStage(t, "validate", func() {
		t.Run("trusted1", makeTrustedNetworkTest(mkHost("trusted1"), "trusted1", lease_ips))
		t.Run("trusted2", makeTrustedNetworkTest(mkHost("trusted2"), "trusted2", lease_ips))
		t.Run("guest1", makeGuestNetworkTest(mkHost("guest1"), "guest1", lease_ips))
		t.Run("guest2", makeGuestNetworkTest(mkHost("guest2"), "guest2", lease_ips))
	})
}

func makeTrustedNetworkTest(host ssh.Host, hostname string, host_ips map[string]string) func(*testing.T) {
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
			// {
			// 	name: "Can ping other trusted hosts",
			// 	check: func(t *testing.T) {
			// 		for k, v := range host_ips {
			// 			if k != hostname && strings.HasPrefix(k, "trusted") {
			// 				CanPing(t, host, v)
			// 			}
			// 		}
			// 	},
			// },
		}

		for _, tt := range tc {
			t.Run(tt.name, func(t *testing.T) {
				tt.check(t)
			})
		}
	}
}

func makeGuestNetworkTest(host ssh.Host, _ string, host_ips map[string]string) func(*testing.T) {
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
			},
			// {
			// 	name: "Can not ping other guest hosts",
			// 	check: func(t *testing.T) {
			// 		for k, v := range host_ips {
			// 			t.Logf("Checking guest host %s (%s)", k, host.Hostname)
			// 			if k != hostname && strings.HasPrefix(k, "guest") {
			// 				CanNotPing(t, host, v)
			// 			}
			// 		}
			// 	},
			// },
			{
				name: "Can not ping trusted hosts",
				check: func(t *testing.T) {
					for k, v := range host_ips {
						if strings.HasPrefix(k, "trusted") {
							CanNotPing(t, host, v)
						}
					}
				},
			},
		}

		for _, tt := range tc {
			t.Run(tt.name, func(t *testing.T) {
				tt.check(t)
			})
		}
	}
}
