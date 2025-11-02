package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/ssh"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
)

func TestSsh(t *testing.T) {
	t.Parallel()

	test_structure.RunTestStage(t, "setup", func() {
		router := ssh.Host{
			Hostname:    "192.168.89.2",
			SshUserName: "admin",
			Password:    "admin",
		}

		// Cleanup connection tracking
		RunSshCommand(t, router, "/ip/firewall/connection/remove [find]")
	})

	test_structure.RunTestStage(t, "validate", func() {
		t.Run("trusted", testTrustedNetwork)
		t.Run("guest", testGuestNetwork)
	})
}

func testTrustedNetwork(t *testing.T) {
	host := ssh.Host{
		Hostname:    "192.168.89.4",
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

func testGuestNetwork(t *testing.T) {
	host := ssh.Host{
		Hostname:    "192.168.89.5",
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
