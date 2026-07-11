package agent

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/tirosh/vitalserver-platform-agent/internal/owner"
)

type deliveryRunnerCall struct {
	executable string
	arguments  []string
}

type stubDeliveryRunner struct {
	calls  []deliveryRunnerCall
	output []byte
	err    error
}

func (runner *stubDeliveryRunner) Run(_ context.Context, executable string, arguments ...string) ([]byte, error) {
	runner.calls = append(runner.calls, deliveryRunnerCall{executable: executable, arguments: append([]string(nil), arguments...)})
	return runner.output, runner.err
}

func TestDeliverySchedulesDurableTransientUpdateOperation(t *testing.T) {
	root := t.TempDir()
	workflow := filepath.Join(root, "platform-workflow.json")
	runner := &stubDeliveryRunner{}
	bundle := filepath.Join(root, "update.tar.gz")
	if err := os.WriteFile(bundle, []byte("bundle"), 0o600); err != nil {
		t.Fatal(err)
	}
	digests := filepath.Join(root, "trusted-bundle-digests.json")
	digest := sha256.Sum256([]byte("bundle"))
	if err := os.WriteFile(digests, []byte(fmt.Sprintf(`{"schemaVersion":1,"sha256":["%x"]}`, digest)), 0o600); err != nil {
		t.Fatal(err)
	}
	controller := &deliveryController{
		config: DeliveryConfig{
			WorkflowDocument:     workflow,
			UpdateTool:           "/opt/vitalserver/current/tools/update-linux.py",
			SchedulerExecutable:  "/usr/bin/systemd-run",
			SchedulerKind:        DeliverySchedulerSystemdTransient,
			ApplyPolicy:          DeliveryApplyPolicySHA256Allowlist,
			TrustedBundleDigests: digests,
		},
		runner: runner,
		now:    func() time.Time { return time.Date(2026, 7, 11, 0, 0, 0, 0, time.UTC) },
	}
	operation, err := controller.schedule(context.Background(), "apply", bundle)
	if err != nil {
		t.Fatal(err)
	}
	if operation.State != "accepted" || operation.Kind != "update-apply" || !strings.HasPrefix(operation.OperationID, "workflow-") {
		t.Fatalf("unexpected operation: %+v", operation)
	}
	resource := owner.ReadPlatformWorkflow(workflow)
	if resource.State != "loaded" || resource.Operation == nil || resource.Operation.OperationID != operation.OperationID {
		t.Fatalf("accepted operation owner was not persisted: %+v", resource)
	}
	if len(runner.calls) != 1 || runner.calls[0].executable != "/usr/bin/systemd-run" {
		t.Fatalf("scheduler was not called: %+v", runner.calls)
	}
	arguments := strings.Join(runner.calls[0].arguments, " ")
	for _, expected := range []string{
		"--no-block", "--service-type=exec", "update-linux.py apply",
		"--bundle " + bundle, "--operation-document " + workflow,
	} {
		if !strings.Contains(arguments, expected) {
			t.Fatalf("scheduler arguments miss %q: %s", expected, arguments)
		}
	}
}

func TestDeliveryRejectsConcurrentPersistedWorkflow(t *testing.T) {
	root := t.TempDir()
	workflow := filepath.Join(root, "platform-workflow.json")
	runner := &stubDeliveryRunner{}
	controller := &deliveryController{
		config: DeliveryConfig{WorkflowDocument: workflow, UpdateTool: "update", SchedulerExecutable: "schedule", SchedulerKind: DeliverySchedulerSystemdTransient},
		runner: runner,
		now:    time.Now,
	}
	if _, err := controller.schedule(context.Background(), "verify", filepath.Join(root, "one.tar.gz")); err != nil {
		t.Fatal(err)
	}
	if _, err := controller.schedule(context.Background(), "apply", filepath.Join(root, "two.tar.gz")); err == nil || !strings.Contains(err.Error(), "already active") {
		t.Fatalf("active persisted workflow must reject concurrency: %v", err)
	}
	if len(runner.calls) != 1 {
		t.Fatalf("second workflow reached scheduler: %+v", runner.calls)
	}
}

func TestDeliveryPersistsScheduleFailure(t *testing.T) {
	root := t.TempDir()
	workflow := filepath.Join(root, "platform-workflow.json")
	controller := &deliveryController{
		config: DeliveryConfig{WorkflowDocument: workflow, UpdateTool: "update", SchedulerExecutable: "schedule", SchedulerKind: DeliverySchedulerSystemdTransient},
		runner: &stubDeliveryRunner{err: errors.New("systemd unavailable")},
		now:    time.Now,
	}

	operation, err := controller.schedule(context.Background(), "verify", filepath.Join(root, "update.tar.gz"))
	if err == nil || operation.State != "failed" || operation.Failure == nil {
		t.Fatalf("schedule failure was not explicit operation evidence operation=%+v err=%v", operation, err)
	}
	resource := owner.ReadPlatformWorkflow(workflow)
	if resource.Operation == nil || resource.Operation.State != "failed" || resource.Operation.Failure == nil {
		t.Fatalf("schedule failure owner was not persisted: %+v", resource)
	}
}

func TestDeliverySchedulesRollbackAsDurablePlatformWorkflow(t *testing.T) {
	root := t.TempDir()
	runner := &stubDeliveryRunner{}
	controller := &deliveryController{
		config: DeliveryConfig{
			WorkflowDocument:    filepath.Join(root, "workflow.json"),
			RollbackTool:        "/opt/vitalserver/current/tools/rollback-linux.py",
			SchedulerExecutable: "/usr/bin/systemd-run",
			SchedulerKind:       DeliverySchedulerSystemdTransient,
		},
		runner: runner,
		now:    time.Now,
	}
	operation, err := controller.scheduleRollback(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if operation.Kind != "rollback" || operation.State != "accepted" {
		t.Fatalf("unexpected rollback operation: %+v", operation)
	}
	arguments := strings.Join(runner.calls[0].arguments, " ")
	for _, expected := range []string{
		"rollback-linux.py", "--operation-id " + operation.OperationID,
		"--operation-document " + controller.config.WorkflowDocument,
	} {
		if !strings.Contains(arguments, expected) {
			t.Fatalf("rollback scheduler arguments miss %q: %s", expected, arguments)
		}
	}
}

func TestDeliverySchedulesWindowsUninstallWithExplicitMode(t *testing.T) {
	root := t.TempDir()
	runner := &stubDeliveryRunner{}
	controller := &deliveryController{
		config: DeliveryConfig{
			WorkflowDocument:    filepath.Join(root, "workflow.json"),
			UninstallTool:       `C:\Program Files\VitalServer\uninstall-windows.ps1`,
			SchedulerExecutable: `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`,
			SchedulerKind:       DeliverySchedulerWindowsTask,
			SchedulerScript:     `C:\Program Files\VitalServer\schedule-workflow-windows.ps1`,
		},
		runner: runner,
		now:    time.Now,
	}
	operation, err := controller.scheduleUninstall(context.Background(), "clean")
	if err != nil {
		t.Fatal(err)
	}
	if operation.Kind != "uninstall" || operation.State != "accepted" {
		t.Fatalf("unexpected uninstall operation: %+v", operation)
	}
	encoded := argumentAfter(t, runner.calls[0].arguments, "-ArgumentsBase64")
	data, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		t.Fatal(err)
	}
	var arguments []string
	if err := json.Unmarshal(data, &arguments); err != nil {
		t.Fatal(err)
	}
	for _, expected := range []string{"-Mode", "clean", "-OperationId", operation.OperationID} {
		if !containsString(arguments, expected) {
			t.Fatalf("Windows uninstall arguments miss %q: %+v", expected, arguments)
		}
	}
}

func TestDeliverySchedulesSupportExportAsDurablePlatformWorkflow(t *testing.T) {
	root := t.TempDir()
	runner := &stubDeliveryRunner{}
	controller := &deliveryController{
		config: DeliveryConfig{
			WorkflowDocument:    filepath.Join(root, "workflow.json"),
			SupportExportTool:   "/opt/vitalserver/current/tools/support-export-linux.py",
			SchedulerExecutable: "/usr/bin/systemd-run",
			SchedulerKind:       DeliverySchedulerSystemdTransient,
		},
		runner: runner,
		now:    time.Now,
	}
	operation, err := controller.scheduleSupportExport(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if operation.Kind != "support-export" || operation.State != "accepted" || operation.Artifact != nil {
		t.Fatalf("unexpected support export operation: %+v", operation)
	}
	arguments := strings.Join(runner.calls[0].arguments, " ")
	for _, expected := range []string{
		"support-export-linux.py", "--operation-id " + operation.OperationID,
		"--operation-document " + controller.config.WorkflowDocument,
	} {
		if !strings.Contains(arguments, expected) {
			t.Fatalf("support export scheduler arguments miss %q: %s", expected, arguments)
		}
	}
}

func TestDeliveryRejectsBundleMissingFromTrustedDigestOwner(t *testing.T) {
	root := t.TempDir()
	digests := filepath.Join(root, "trusted-bundle-digests.json")
	otherDigest := sha256.Sum256([]byte("other bundle"))
	if err := os.WriteFile(digests, []byte(fmt.Sprintf(`{"schemaVersion":1,"sha256":["%x"]}`, otherDigest)), 0o600); err != nil {
		t.Fatal(err)
	}
	bundle := filepath.Join(root, "update.tar.gz")
	if err := os.WriteFile(bundle, []byte("bundle"), 0o600); err != nil {
		t.Fatal(err)
	}
	runner := &stubDeliveryRunner{}
	controller := &deliveryController{
		config: DeliveryConfig{
			WorkflowDocument: filepath.Join(root, "workflow.json"),
			UpdateTool:       "update", SchedulerExecutable: "schedule",
			SchedulerKind:        DeliverySchedulerSystemdTransient,
			ApplyPolicy:          DeliveryApplyPolicySHA256Allowlist,
			TrustedBundleDigests: digests,
		},
		runner: runner,
		now:    time.Now,
	}
	if _, err := controller.schedule(context.Background(), "apply", bundle); !errors.Is(err, errUpdateBundleUntrusted) {
		t.Fatalf("expected untrusted bundle failure, got %v", err)
	}
	if len(runner.calls) != 0 {
		t.Fatalf("untrusted bundle reached scheduler: %+v", runner.calls)
	}
	if _, err := os.Stat(controller.config.WorkflowDocument); !os.IsNotExist(err) {
		t.Fatalf("untrusted bundle created workflow owner: %v", err)
	}
}

func TestDeliverySummaryRequiresExplicitToolResponse(t *testing.T) {
	runner := &stubDeliveryRunner{output: []byte(`{"summary":"VitalServer Linux 2.0.0"}`)}
	controller := &deliveryController{
		config: DeliveryConfig{UpdateTool: "update", SchedulerKind: DeliverySchedulerSystemdTransient}, runner: runner, now: time.Now,
	}
	summary, err := controller.summarize(context.Background(), "/tmp/update.tar.gz")
	if err != nil || summary.Summary != "VitalServer Linux 2.0.0" {
		t.Fatalf("summary=%+v err=%v", summary, err)
	}
}

func TestDeliveryUsesPowerShellAndScheduledTaskAdapterOnWindows(t *testing.T) {
	root := t.TempDir()
	runner := &stubDeliveryRunner{output: []byte(`{"summary":"VitalServer Windows 2.0.0"}`)}
	controller := &deliveryController{
		config: DeliveryConfig{
			WorkflowDocument:    filepath.Join(root, "workflow.json"),
			UpdateTool:          `C:\Program Files\VitalServer\update-windows.ps1`,
			SchedulerExecutable: `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`,
			SchedulerKind:       DeliverySchedulerWindowsTask,
			SchedulerScript:     `C:\Program Files\VitalServer\schedule-workflow-windows.ps1`,
		},
		runner: runner,
		now:    time.Now,
	}
	bundle := `C:\Updates\VitalServer-Windows.zip`
	if _, err := controller.summarize(context.Background(), bundle); err != nil {
		t.Fatal(err)
	}
	if runner.calls[0].executable != controller.config.SchedulerExecutable || !strings.Contains(strings.Join(runner.calls[0].arguments, " "), "-File "+controller.config.UpdateTool+" summary") {
		t.Fatalf("Windows summary did not use PowerShell tool adapter: %+v", runner.calls[0])
	}
	runner.output = nil
	operation, err := controller.schedule(context.Background(), "verify", bundle)
	if err != nil {
		t.Fatal(err)
	}
	call := runner.calls[1]
	joined := strings.Join(call.arguments, " ")
	if call.executable != controller.config.SchedulerExecutable || !strings.Contains(joined, "-File "+controller.config.SchedulerScript) {
		t.Fatalf("Windows workflow did not use Scheduled Task adapter: %+v", call)
	}
	encoded := argumentAfter(t, call.arguments, "-ArgumentsBase64")
	data, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		t.Fatal(err)
	}
	var arguments []string
	if err := json.Unmarshal(data, &arguments); err != nil {
		t.Fatal(err)
	}
	for _, expected := range []string{"verify", "-Bundle", bundle, "-OperationId", operation.OperationID} {
		if !containsString(arguments, expected) {
			t.Fatalf("Windows task arguments miss %q: %+v", expected, arguments)
		}
	}
}

func argumentAfter(t *testing.T, arguments []string, name string) string {
	t.Helper()
	for index, argument := range arguments {
		if argument == name && index+1 < len(arguments) {
			return arguments[index+1]
		}
	}
	t.Fatalf("argument is missing: %s in %+v", name, arguments)
	return ""
}

func containsString(values []string, expected string) bool {
	for _, value := range values {
		if value == expected {
			return true
		}
	}
	return false
}
