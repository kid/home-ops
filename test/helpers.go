package test

import (
	"fmt"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/ssh"
	"github.com/stretchr/testify/assert"
)

func RunSshCommand(t *testing.T, host ssh.Host, command string) string {
	return retry.DoWithTimeout(t, fmt.Sprintf("Running %s", command), 10*time.Second, func() (string, error) {
		return ssh.CheckSshCommandE(t, host, command)
	})
}

func CanPing(t *testing.T, host ssh.Host, target string) {
	retry.DoWithTimeout(t, fmt.Sprintf("ping %s", target), 10*time.Second, func() (string, error) {
		text, err := ssh.CheckSshCommandE(t, host, fmt.Sprintf("/ping %s count=1", target))
		assert.NoError(t, err)
		assert.Contains(t, text, "sent=1 received=1 packet-loss=0%", "Expected ping to succeed")

		return "", nil
	})
}

func CanNotPing(t *testing.T, host ssh.Host, target string) {
	retry.DoWithTimeout(t, fmt.Sprintf("ping %s", target), 10*time.Second, func() (string, error) {
		text, err := ssh.CheckSshCommandE(t, host, fmt.Sprintf("/ping %s count=1", target))
		assert.NoError(t, err)
		assert.Contains(t, text, "sent=1 received=0 packet-loss=100%", "Expected ping to fail")

		return "", nil
	})
}
