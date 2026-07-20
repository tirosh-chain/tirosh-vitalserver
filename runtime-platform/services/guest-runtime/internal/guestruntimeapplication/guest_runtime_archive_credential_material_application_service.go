package guestruntimeapplication

import (
	"context"
	"fmt"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

// GuestRuntimeArchiveCredentialMaterialApplicationService presents the one
// Guest secret-material owner through explicit, non-secret outcomes. It owns
// no persistent state: C51 must not be copied to the Guest Runtime SQLite
// database, an Operation, a receipt, telemetry, or a response history.
type GuestRuntimeArchiveCredentialMaterialApplicationService struct {
	owner GuestRuntimeArchiveCredentialMaterialOwner
	clock GuestRuntimeClock
}

func NewGuestRuntimeArchiveCredentialMaterialApplicationService(owner GuestRuntimeArchiveCredentialMaterialOwner, clock GuestRuntimeClock) (*GuestRuntimeArchiveCredentialMaterialApplicationService, error) {
	if owner == nil || clock == nil {
		return nil, fmt.Errorf("Guest archive credential-material owner and clock are required")
	}
	if reference := owner.CredentialReference(); !guestruntimedomain.ValidIdentifier(reference.Kind) || !guestruntimedomain.ValidIdentifier(reference.ID) {
		return nil, fmt.Errorf("Guest archive credential-material owner has no valid C46 credential reference")
	}
	return &GuestRuntimeArchiveCredentialMaterialApplicationService{owner: owner, clock: clock}, nil
}

func (service *GuestRuntimeArchiveCredentialMaterialApplicationService) ReadVitalServerIndexedLibraryCredentialMaterialAvailability(ctx context.Context) guestruntimedomain.VitalServerIndexedLibraryCredentialMaterialAvailability {
	reference := service.owner.CredentialReference()
	state, issue := service.owner.ObserveVitalServerIndexedLibraryCredentialMaterial(ctx)
	return guestruntimedomain.VitalServerIndexedLibraryCredentialMaterialAvailability{
		SchemaVersion:       guestruntimedomain.SchemaVersion,
		State:               state,
		ObservedAt:          guestruntimedomain.Timestamp(service.clock.Now()),
		CredentialReference: guestruntimedomain.OptionalVitalServerIndexedLibraryCredentialReference(reference),
		Issue:               issue,
	}
}

func (service *GuestRuntimeArchiveCredentialMaterialApplicationService) ProvisionVitalServerIndexedLibraryCredentialMaterial(ctx context.Context, material guestruntimedomain.VitalServerIndexedLibraryCredentialMaterial) guestruntimedomain.VitalServerIndexedLibraryCredentialMaterialProvisioningOutcome {
	now := guestruntimedomain.Timestamp(service.clock.Now())
	if issue := guestruntimedomain.ValidateVitalServerIndexedLibraryCredentialMaterial(material); issue != nil {
		return guestruntimedomain.VitalServerIndexedLibraryCredentialMaterialProvisioningOutcome{
			SchemaVersion:       guestruntimedomain.SchemaVersion,
			State:               "rejected",
			ObservedAt:          now,
			CredentialReference: guestruntimedomain.OptionalVitalServerIndexedLibraryCredentialReference(material.CredentialReference),
			Issue:               issue,
		}
	}
	if issue := service.owner.ProvisionVitalServerIndexedLibraryCredentialMaterial(ctx, material); issue != nil {
		return guestruntimedomain.VitalServerIndexedLibraryCredentialMaterialProvisioningOutcome{
			SchemaVersion:       guestruntimedomain.SchemaVersion,
			State:               "failed",
			ObservedAt:          now,
			CredentialReference: guestruntimedomain.OptionalVitalServerIndexedLibraryCredentialReference(material.CredentialReference),
			Issue:               issue,
		}
	}
	return guestruntimedomain.VitalServerIndexedLibraryCredentialMaterialProvisioningOutcome{
		SchemaVersion:       guestruntimedomain.SchemaVersion,
		State:               "provisioned",
		ObservedAt:          now,
		CredentialReference: guestruntimedomain.OptionalVitalServerIndexedLibraryCredentialReference(material.CredentialReference),
	}
}
