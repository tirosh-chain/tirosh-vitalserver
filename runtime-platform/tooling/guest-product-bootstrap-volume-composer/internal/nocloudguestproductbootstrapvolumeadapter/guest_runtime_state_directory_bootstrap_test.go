package nocloudguestproductbootstrapvolumeadapter

import (
	"strings"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-bootstrap-volume-composer/internal/guestproductbootstrapvolumeplan"
)

func TestRenderGuestOwnedBootstrapScriptCreatesDeclaredGuestRuntimeStateDirectoryBeforeStartingService(t *testing.T) {
	plan := guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{
		VolumeLabel:     "CIDATA",
		ServiceUnitName: "vitalserver-guest-product.service",
		GuestRuntimeStateDirectory: guestproductbootstrapvolumeplan.DeclaredGuestDirectory{
			DirectoryPath: "/var/lib/vitalserver/guest-runtime",
			DirectoryMode: "0700",
		},
	}

	script, err := renderGuestOwnedBootstrapScript(plan)
	if err != nil {
		t.Fatalf("render Guest bootstrap script: %v", err)
	}
	stateDirectoryProvisioning := "install -d -m 0700 \"/var/lib/vitalserver/guest-runtime\""
	serviceStart := "systemctl start vitalserver-guest-product.service"
	stateDirectoryOffset := strings.Index(script, stateDirectoryProvisioning)
	serviceStartOffset := strings.Index(script, serviceStart)
	if stateDirectoryOffset < 0 || serviceStartOffset < 0 || stateDirectoryOffset > serviceStartOffset {
		t.Fatalf("Guest Runtime state directory must be provisioned before C38 starts C37:\n%s", script)
	}
}

func TestRenderGuestOwnedBootstrapScriptInstallsAndStartsOnlyDeclaredChronyService(t *testing.T) {
	plan := guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{
		VolumeLabel: "CIDATA", ServiceUnitName: "vitalserver-guest-product.service",
		GuestRuntimeStateDirectory: guestproductbootstrapvolumeplan.DeclaredGuestDirectory{DirectoryPath: "/var/lib/vitalserver/guest-runtime", DirectoryMode: "0700"},
		GuestTimeSynchronization:   &guestproductbootstrapvolumeplan.DeclaredGuestTimeSynchronization{PackageManager: "apt", PackageName: "chrony", ServiceName: "chrony.service"},
	}

	script, err := renderGuestOwnedBootstrapScript(plan)
	if err != nil {
		t.Fatalf("render Guest bootstrap script: %v", err)
	}
	packageInstall := "apt-get install --yes --no-install-recommends chrony"
	serviceRestart := "systemctl restart chrony.service"
	productStart := "systemctl start vitalserver-guest-product.service"
	if packageOffset, restartOffset, productOffset := strings.Index(script, packageInstall), strings.Index(script, serviceRestart), strings.Index(script, productStart); packageOffset < 0 || restartOffset < 0 || productOffset < 0 || packageOffset > restartOffset || restartOffset > productOffset {
		t.Fatalf("Chrony must be installed and restarted before product startup:\n%s", script)
	}
}

func TestRenderGuestOwnedBootstrapScriptExplicitlyInitializesBundledImageSetStateBeforeStartingManager(t *testing.T) {
	plan := guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{
		VolumeLabel: "CIDATA", ServiceUnitName: "vitalserver-guest-product.service",
		GuestRuntimeStateDirectory: guestproductbootstrapvolumeplan.DeclaredGuestDirectory{DirectoryPath: "/var/lib/vitalserver/guest-runtime", DirectoryMode: "0700"},
		GuestBundledUpstreamImageSetManager: &guestproductbootstrapvolumeplan.DeclaredGuestBundledUpstreamImageSetManager{
			ManagerID: "bundled-upstream-image-set-manager", ExecutablePath: "/opt/vitalserver/current/bin/guest-bundled-upstream-image-set-manager", ConfigurationPath: "/opt/vitalserver/current/config/guest-bundled-upstream-image-set-manager.json",
			StateDirectory:           guestproductbootstrapvolumeplan.DeclaredGuestDirectory{DirectoryPath: "/var/lib/vitalserver/bundled-upstream-image-sets", DirectoryMode: "0700"},
			ContainerEngineBootstrap: guestproductbootstrapvolumeplan.DeclaredGuestContainerEngineBootstrap{PackageManager: "apt", PackageName: "docker.io", ServiceName: "docker.service"},
			ServiceUnitName:          "vitalserver-guest-bundled-upstream-image-set-manager.service", InitialActiveImageSetState: "unprovisioned",
		},
	}

	script, err := renderGuestOwnedBootstrapScript(plan)
	if err != nil {
		t.Fatalf("render Guest bootstrap script: %v", err)
	}
	stateDirectory := "install -d -m 0700 \"/var/lib/vitalserver/bundled-upstream-image-sets\""
	engineInstall := "apt-get install --yes --no-install-recommends docker.io"
	engineStart := "systemctl start docker.service"
	initializer := "\"/opt/vitalserver/current/bin/guest-bundled-upstream-image-set-manager\" --configuration \"/opt/vitalserver/current/config/guest-bundled-upstream-image-set-manager.json\" --mode initialize-active-image-set"
	managerStart := "systemctl start vitalserver-guest-bundled-upstream-image-set-manager.service"
	if engineInstallOffset, engineStartOffset, stateOffset, initializationOffset, startOffset := strings.Index(script, engineInstall), strings.Index(script, engineStart), strings.Index(script, stateDirectory), strings.Index(script, initializer), strings.Index(script, managerStart); engineInstallOffset < 0 || engineStartOffset < 0 || stateOffset < 0 || initializationOffset < 0 || startOffset < 0 || engineInstallOffset > engineStartOffset || engineStartOffset > stateOffset || stateOffset > initializationOffset || initializationOffset > startOffset {
		t.Fatalf("C40 must provision and initialize C64 state before starting it:\n%s", script)
	}
	if strings.Contains(script, "docker load") || strings.Contains(script, "docker compose") {
		t.Fatalf("C40 must not invoke the C64 container engine:\n%s", script)
	}
}
