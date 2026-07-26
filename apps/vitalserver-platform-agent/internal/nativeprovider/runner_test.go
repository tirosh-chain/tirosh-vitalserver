package nativeprovider

import (
	"reflect"
	"testing"
	"time"

	"github.com/tirosh/vitalserver-platform-agent/internal/provider"
)

func TestComposeArgumentsUseExplicitSharedProjectName(t *testing.T) {
	config := Config{
		ComposeEnvironmentFile: "/etc/vitalserver/runtime.env",
		ComposeProjectName:     "vitalserver",
		ComposeFile:            "/opt/vitalserver/current/runtime-bundle/compose.yaml",
		ProjectDirectory:       "/opt/vitalserver/current/runtime-bundle",
	}
	want := []string{
		"compose",
		"--env-file", "/etc/vitalserver/runtime.env",
		"--project-name", "vitalserver",
		"--file", "/opt/vitalserver/current/runtime-bundle/compose.yaml",
		"--project-directory", "/opt/vitalserver/current/runtime-bundle",
		"up", "--detach", "--remove-orphans",
	}

	if got := composeArguments(config, "up", "--detach", "--remove-orphans"); !reflect.DeepEqual(got, want) {
		t.Fatalf("compose arguments=%v want=%v", got, want)
	}
}

func TestNewRunnerUsesExplicitReadinessProbeTimeout(t *testing.T) {
	runner := NewRunner(Config{ReadinessProbeTimeoutSeconds: 20})
	probe, ok := runner.Probe.(provider.HTTPReadinessProbe)
	if !ok {
		t.Fatalf("readiness probe type=%T", runner.Probe)
	}
	if probe.Client.Timeout != 20*time.Second {
		t.Fatalf("readiness probe timeout=%s", probe.Client.Timeout)
	}
}
