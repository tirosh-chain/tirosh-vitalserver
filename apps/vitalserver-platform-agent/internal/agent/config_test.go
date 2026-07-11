package agent

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLoadConfigRequiresEveryServiceRoleExplicitly(t *testing.T) {
	path := writeConfig(t, `{
  "schemaVersion": 1,
  "listenAddress": "127.0.0.1:18321",
  "apiToken": "token",
  "runtimeExecutable": "runtime",
  "runtimeEndpointDocument": "endpoint.json",
  "runtimeProviderDocument": "provider.json",
  "operationLeaseDocument": "lease.json",
  "runtimeControllerPort": 18330,
  "pwaDirectory": "",
  "platformServices": {
    "runtime-provider": null,
    "public-proxy": null,
    "log-sync": null,
    "sleep-prevention": null
  }
}`)

	_, err := LoadConfig(path)
	if err == nil || !strings.Contains(err.Error(), "watchdog") {
		t.Fatalf("missing role must be explicit: %v", err)
	}
}

func TestLoadConfigRejectsUnknownAndEmptyServiceBindings(t *testing.T) {
	for name, services := range map[string]string{
		"unknown": `{
      "runtime-provider": null, "public-proxy": null, "log-sync": null,
      "sleep-prevention": null, "watchdog": null, "guest-stack": "bad"
    }`,
		"empty": `{
      "runtime-provider": "", "public-proxy": null, "log-sync": null,
      "sleep-prevention": null, "watchdog": null
    }`,
	} {
		t.Run(name, func(t *testing.T) {
			path := writeConfig(t, `{
  "schemaVersion": 1,
  "listenAddress": "127.0.0.1:18321",
  "apiToken": "token",
  "runtimeExecutable": "runtime",
  "runtimeEndpointDocument": "endpoint.json",
  "runtimeProviderDocument": "provider.json",
  "operationLeaseDocument": "lease.json",
  "runtimeControllerPort": 18330,
  "pwaDirectory": "",
  "platformServices": `+services+`
}`)
			if _, err := LoadConfig(path); err == nil {
				t.Fatal("invalid service binding must fail configuration")
			}
		})
	}
}

func TestLoadConfigRequiresDigestOwnerOnlyForSHA256ApplyPolicy(t *testing.T) {
	for name, delivery := range map[string]string{
		"verify-only-with-digest": `{
      "workflowDocument":"workflow.json", "updateTool":"update", "rollbackTool":"rollback", "schedulerExecutable":"schedule", "schedulerKind":"systemd-transient",
      "applyPolicy":"verify-only", "trustedBundleDigests":"trusted.json"
    }`,
		"allowlist-without-digest": `{
      "workflowDocument":"workflow.json", "updateTool":"update", "rollbackTool":"rollback", "schedulerExecutable":"schedule", "schedulerKind":"systemd-transient",
      "applyPolicy":"sha256-allowlist"
    }`,
		"unknown-policy": `{
      "workflowDocument":"workflow.json", "updateTool":"update", "rollbackTool":"rollback", "schedulerExecutable":"schedule", "schedulerKind":"systemd-transient",
      "applyPolicy":"guess"
    }`,
	} {
		t.Run(name, func(t *testing.T) {
			path := writeConfig(t, validConfigWithDelivery(delivery))
			if _, err := LoadConfig(path); err == nil {
				t.Fatal("invalid delivery trust policy must fail configuration")
			}
		})
	}

	path := writeConfig(t, validConfigWithDelivery(`{
    "workflowDocument":"workflow.json", "updateTool":"update", "rollbackTool":"rollback", "schedulerExecutable":"schedule", "schedulerKind":"systemd-transient",
    "applyPolicy":"sha256-allowlist", "trustedBundleDigests":"trusted.json"
  }`))
	config, err := LoadConfig(path)
	if err != nil {
		t.Fatal(err)
	}
	want := filepath.Join(filepath.Dir(path), "trusted.json")
	if config.Delivery == nil || config.Delivery.TrustedBundleDigests != want {
		t.Fatalf("trusted digest owner path was not resolved: %+v", config.Delivery)
	}
}

func TestLoadConfigRequiresSchedulerSpecificFields(t *testing.T) {
	for name, delivery := range map[string]string{
		"systemd-with-script": `{
      "workflowDocument":"workflow.json", "updateTool":"update", "rollbackTool":"rollback",
      "schedulerExecutable":"schedule", "schedulerKind":"systemd-transient", "schedulerScript":"task.ps1",
      "applyPolicy":"verify-only"
    }`,
		"windows-without-script": `{
      "workflowDocument":"workflow.json", "updateTool":"update.ps1", "rollbackTool":"rollback.ps1",
      "schedulerExecutable":"powershell.exe", "schedulerKind":"windows-scheduled-task",
      "applyPolicy":"verify-only"
    }`,
		"unknown-scheduler": `{
      "workflowDocument":"workflow.json", "updateTool":"update", "rollbackTool":"rollback",
      "schedulerExecutable":"schedule", "schedulerKind":"guess",
      "applyPolicy":"verify-only"
    }`,
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := LoadConfig(writeConfig(t, validConfigWithDelivery(delivery))); err == nil {
				t.Fatal("invalid scheduler-specific delivery config must fail")
			}
		})
	}

	path := writeConfig(t, validConfigWithDelivery(`{
    "workflowDocument":"workflow.json", "updateTool":"update.ps1", "rollbackTool":"rollback.ps1",
    "schedulerExecutable":"powershell.exe", "schedulerKind":"windows-scheduled-task", "schedulerScript":"task.ps1",
    "applyPolicy":"verify-only"
  }`))
	config, err := LoadConfig(path)
	if err != nil {
		t.Fatal(err)
	}
	if config.Delivery == nil || config.Delivery.SchedulerScript != filepath.Join(filepath.Dir(path), "task.ps1") {
		t.Fatalf("Windows scheduler script path was not resolved: %+v", config.Delivery)
	}
}

func validConfigWithDelivery(delivery string) string {
	return `{
  "schemaVersion":1,
  "listenAddress":"127.0.0.1:18321",
  "apiToken":"token",
  "runtimeExecutable":"runtime",
  "runtimeEndpointDocument":"endpoint.json",
  "runtimeProviderDocument":"provider.json",
  "operationLeaseDocument":"lease.json",
  "runtimeControllerPort":18330,
  "pwaDirectory":"",
  "platformServices":{
    "runtime-provider":null, "public-proxy":null, "log-sync":null,
    "sleep-prevention":null, "watchdog":null
  },
  "delivery":` + delivery + `
}`
}

func writeConfig(t *testing.T, document string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "platform-agent.json")
	if err := os.WriteFile(path, []byte(document), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}
