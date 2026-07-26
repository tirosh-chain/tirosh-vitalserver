//go:build windows

package updateexecutionreportfile

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-updater/internal/hostupdaterdomain"
)

func TestRejectSymbolicLinkPathComponentsPreservesWindowsVolumeRoot(t *testing.T) {
	path := filepath.Join(t.TempDir(), "report.json")
	if err := rejectSymbolicLinkPathComponents(path); err != nil {
		t.Fatalf("inspect absolute Windows path from its volume root: %v", err)
	}
}

func TestWriteStagedProductUpdateExecutionReportRejectsWindowsNetworkPath(t *testing.T) {
	err := WriteStagedProductUpdateExecutionReport(
		`\\server\share\execution-report.json`,
		hostupdaterdomain.StagedProductUpdateExecutionReport{},
	)
	if err == nil || !strings.Contains(err.Error(), "Host-local volume") {
		t.Fatalf("expected Windows network path to be rejected explicitly, got %v", err)
	}
}

func TestRejectSymbolicLinkPathComponentsRejectsWindowsJunction(t *testing.T) {
	root := t.TempDir()
	target := filepath.Join(root, "target")
	junction := filepath.Join(root, "junction")
	if err := os.Mkdir(target, 0o700); err != nil {
		t.Fatal(err)
	}
	command := exec.Command("cmd.exe", "/c", "mklink", "/J", junction, target)
	if output, err := command.CombinedOutput(); err != nil {
		t.Fatalf("create Windows junction fixture: %v output=%s", err, output)
	}
	err := rejectSymbolicLinkPathComponents(filepath.Join(junction, "report.json"))
	if err == nil {
		t.Fatal("expected Windows junction path component to be rejected")
	}
	if !strings.Contains(err.Error(), "symbolic link or redirecting reparse point") {
		t.Fatalf("unexpected Windows junction rejection: %v", err)
	}
}

func TestWriteStagedProductUpdateExecutionReportRejectsWindowsJunctionWithoutPublishing(t *testing.T) {
	root := t.TempDir()
	target := filepath.Join(root, "target")
	junction := filepath.Join(root, "junction")
	if err := os.Mkdir(target, 0o700); err != nil {
		t.Fatal(err)
	}
	command := exec.Command("cmd.exe", "/c", "mklink", "/J", junction, target)
	if output, err := command.CombinedOutput(); err != nil {
		t.Fatalf("create Windows junction fixture: %v output=%s", err, output)
	}
	targetReport := filepath.Join(target, "execution-report.json")
	err := WriteStagedProductUpdateExecutionReport(
		filepath.Join(junction, "execution-report.json"),
		hostupdaterdomain.StagedProductUpdateExecutionReport{},
	)
	if err == nil {
		t.Fatal("expected C28 publication through a Windows junction to be rejected")
	}
	if _, statErr := os.Lstat(targetReport); !errors.Is(statErr, os.ErrNotExist) {
		t.Fatalf("C28 junction rejection must not publish into the target: %v", statErr)
	}
}
