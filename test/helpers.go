package test

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/ssh"
)

func RunSshCommand(t *testing.T, host ssh.Host, command string) string {
	return retry.DoWithTimeout(t, fmt.Sprintf("Running %s", command), 10*time.Second, func() (string, error) {
		return ssh.CheckSshCommandE(t, host, command)
	})
}

func CanPing(t *testing.T, host ssh.Host, target string) {
	retry.DoWithTimeout(t, fmt.Sprintf("ping %s", target), 10*time.Second, func() (string, error) {
		text, err := ssh.CheckSshCommandE(t, host, fmt.Sprintf("/ping %s count=1", target))
		if err != nil {
			return "", err
		}

		if !strings.Contains(text, "sent=1 received=1 packet-loss=0%") {
			return "", fmt.Errorf("Expected ping to succeed but it failed: %s", text)
		}

		return "", nil
	})
}

func CanNotPing(t *testing.T, host ssh.Host, target string) {
	retry.DoWithTimeout(t, fmt.Sprintf("ping %s", target), 10*time.Second, func() (string, error) {
		text, err := ssh.CheckSshCommandE(t, host, fmt.Sprintf("/ping %s count=1", target))
		if err != nil {
			return "", err
		}

		if !strings.Contains(text, "sent=1 received=0 packet-loss=100%") {
			return "", fmt.Errorf("Expected ping to fail but it succeeded: %s", text)
		}

		return "", nil
	})
}
