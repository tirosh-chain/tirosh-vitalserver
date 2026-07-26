//go:build darwin

package macoshostinstallationfootprint

import (
	"context"
	"fmt"
	"path/filepath"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

// This is a read-only platform contract probe. It prevents a fake launchctl
// result from becoming the only source of truth for an absent system service
// on the macOS release that builds the Host package.
func TestMacOSLaunchctlPrintRecognizesActualAbsentSystemService(t *testing.T) {
	serviceName := fmt.Sprintf("com.tirosh.vitalserver.installation-probe-%d", time.Now().UnixNano())
	observer, err := NewMacOSHostInstallationFootprintObserver("/usr/sbin/pkgutil", "/bin/launchctl")
	if err != nil {
		t.Fatal(err)
	}
	service := hostinstallationmanagerdomain.HostProductRequiredService{
		Role:             "installation-probe",
		Manager:          "launchd",
		Name:             serviceName,
		DefinitionPath:   filepath.Join(t.TempDir(), "missing.plist"),
		DefinitionSHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
	}
	observation := observer.observeRequiredService(context.Background(), service)
	if observation.State != "absent" {
		t.Fatalf("launchctl absence contract changed: service=%+v", observation)
	}
}
