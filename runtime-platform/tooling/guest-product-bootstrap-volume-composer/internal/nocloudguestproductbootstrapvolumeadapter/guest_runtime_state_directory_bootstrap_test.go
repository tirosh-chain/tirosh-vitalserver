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
