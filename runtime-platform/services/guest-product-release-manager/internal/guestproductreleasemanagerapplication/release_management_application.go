// Package guestproductreleasemanagerapplication orchestrates C59 effects.
// It owns no filesystem or systemd implementation: adapters report those
// effects explicitly through the ports declared here.
package guestproductreleasemanagerapplication

import (
	"context"
	"fmt"
	"io"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-manager/internal/guestproductreleasemanagerdomain"
)

type ReleaseOperationRepository interface {
	ReadReleaseOperation(context.Context, string) (guestproductreleasemanagerdomain.GuestProductReleaseOperation, bool, error)
	WriteReleaseOperation(context.Context, guestproductreleasemanagerdomain.GuestProductReleaseOperation) error
}

type ReleaseArchiveStager interface {
	StageReleaseArchive(context.Context, guestproductreleasemanagerdomain.GuestProductReleaseUpdateCommand, io.Reader) *ReleaseManagementFailure
}

type CurrentReleaseLinkManager interface {
	ReadActiveReleaseID(context.Context) (string, *ReleaseManagementFailure)
	ActivateRelease(context.Context, guestproductreleasemanagerdomain.ReleaseReference) *ReleaseManagementFailure
}

type ManagedGuestProductService interface {
	RestartManagedGuestProduct(context.Context) *ReleaseManagementFailure
}

type GuestProductHealthProbe interface {
	WaitForGuestProductHealth(context.Context) *ReleaseManagementFailure
}

type ReleaseManagementClock interface{ Now() string }

// ReleaseManagementFailure preserves an adapter's reported semantic state.
// Application workflow never guesses that a systemctl or HTTP error is a
// product failure versus an unavailable dependency.
type ReleaseManagementFailure struct {
	State string
	Issue guestproductreleasemanagerdomain.Issue
}

func (failure *ReleaseManagementFailure) valid() bool {
	return failure != nil && (failure.State == guestproductreleasemanagerdomain.OperationStateFailed || failure.State == guestproductreleasemanagerdomain.OperationStateUnavailable) && failure.Issue.Code != "" && failure.Issue.Message != ""
}

type GuestProductReleaseManagerApplicationService struct {
	configuration guestproductreleasemanagerdomain.ManagerConfiguration
	repository    ReleaseOperationRepository
	stager        ReleaseArchiveStager
	current       CurrentReleaseLinkManager
	service       ManagedGuestProductService
	health        GuestProductHealthProbe
	clock         ReleaseManagementClock
}

func NewGuestProductReleaseManagerApplicationService(
	configuration guestproductreleasemanagerdomain.ManagerConfiguration,
	repository ReleaseOperationRepository,
	stager ReleaseArchiveStager,
	current CurrentReleaseLinkManager,
	service ManagedGuestProductService,
	health GuestProductHealthProbe,
	clock ReleaseManagementClock,
) (*GuestProductReleaseManagerApplicationService, error) {
	if err := guestproductreleasemanagerdomain.ValidateManagerConfiguration(configuration); err != nil {
		return nil, err
	}
	if repository == nil || stager == nil || current == nil || service == nil || health == nil || clock == nil {
		return nil, fmt.Errorf("C59 repository, stager, current-link manager, service controller, health probe, and clock are required")
	}
	return &GuestProductReleaseManagerApplicationService{configuration: configuration, repository: repository, stager: stager, current: current, service: service, health: health, clock: clock}, nil
}

// ApplyReleaseUpdate performs the only Guest Product current-link transition.
// A target health failure always attempts to restore the expected current
// release. The terminal record says rolled-back only after the restored
// release has also passed the declared health probe.
func (service *GuestProductReleaseManagerApplicationService) ApplyReleaseUpdate(
	context context.Context,
	command guestproductreleasemanagerdomain.GuestProductReleaseUpdateCommand,
	archive io.Reader,
) (guestproductreleasemanagerdomain.GuestProductReleaseOperation, error) {
	if archive == nil {
		return guestproductreleasemanagerdomain.GuestProductReleaseOperation{}, fmt.Errorf("C59 release archive is required")
	}
	if err := guestproductreleasemanagerdomain.ValidateReleaseUpdateCommand(service.configuration, command); err != nil {
		return guestproductreleasemanagerdomain.GuestProductReleaseOperation{}, err
	}
	existing, found, err := service.repository.ReadReleaseOperation(context, command.UpdateID)
	if err != nil {
		return guestproductreleasemanagerdomain.GuestProductReleaseOperation{}, fmt.Errorf("read C59 release operation: %w", err)
	}
	if found {
		if !guestproductreleasemanagerdomain.SameReleaseUpdateCommand(existing, command) {
			return guestproductreleasemanagerdomain.GuestProductReleaseOperation{}, fmt.Errorf("C59 update id already belongs to a different release command")
		}
		return existing, nil
	}
	activeReleaseID, currentFailure := service.current.ReadActiveReleaseID(context)
	if currentFailure != nil {
		return service.persistTerminalFailure(context, guestproductreleasemanagerdomain.NewReleaseOperation(command, service.clock.Now()), currentFailure)
	}
	if activeReleaseID != command.ExpectedActiveReleaseID {
		return service.persistTerminalFailure(context, guestproductreleasemanagerdomain.NewReleaseOperation(command, service.clock.Now()), &ReleaseManagementFailure{State: guestproductreleasemanagerdomain.OperationStateFailed, Issue: guestproductreleasemanagerdomain.Issue{Code: "active-release-id-mismatch", Message: "declared expected active release does not match the current release", Dependency: "guest-product-release-link"}})
	}
	operation := guestproductreleasemanagerdomain.NewReleaseOperation(command, service.clock.Now())
	if err := service.repository.WriteReleaseOperation(context, operation); err != nil {
		return guestproductreleasemanagerdomain.GuestProductReleaseOperation{}, fmt.Errorf("persist C59 received release operation: %w", err)
	}
	if failure := service.stager.StageReleaseArchive(context, command, archive); failure != nil {
		return service.persistTerminalFailure(context, operation, failure)
	}
	operation, err = guestproductreleasemanagerdomain.MarkReleaseStaged(operation, service.clock.Now())
	if err != nil {
		return guestproductreleasemanagerdomain.GuestProductReleaseOperation{}, err
	}
	if err := service.repository.WriteReleaseOperation(context, operation); err != nil {
		return guestproductreleasemanagerdomain.GuestProductReleaseOperation{}, fmt.Errorf("persist C59 staged release operation: %w", err)
	}
	operation, err = guestproductreleasemanagerdomain.BeginReleaseActivation(operation, service.clock.Now())
	if err != nil {
		return guestproductreleasemanagerdomain.GuestProductReleaseOperation{}, err
	}
	if err := service.repository.WriteReleaseOperation(context, operation); err != nil {
		return guestproductreleasemanagerdomain.GuestProductReleaseOperation{}, fmt.Errorf("persist C59 applying release operation: %w", err)
	}
	if failure := service.current.ActivateRelease(context, guestproductreleasemanagerdomain.ReleaseReference{ReleaseID: command.TargetRelease.ReleaseID, ReleaseDirectory: command.TargetRelease.ReleaseDirectory}); failure != nil {
		return service.persistTerminalFailure(context, operation, failure)
	}
	if failure := service.service.RestartManagedGuestProduct(context); failure != nil {
		return service.rollbackAfterTargetFailure(context, operation, failure)
	}
	if failure := service.health.WaitForGuestProductHealth(context); failure != nil {
		return service.rollbackAfterTargetFailure(context, operation, failure)
	}
	operation, err = guestproductreleasemanagerdomain.CompleteReleaseActivation(operation, service.clock.Now())
	if err != nil {
		return guestproductreleasemanagerdomain.GuestProductReleaseOperation{}, err
	}
	if err := service.repository.WriteReleaseOperation(context, operation); err != nil {
		return guestproductreleasemanagerdomain.GuestProductReleaseOperation{}, fmt.Errorf("persist C59 succeeded release operation: %w", err)
	}
	return operation, nil
}

func (service *GuestProductReleaseManagerApplicationService) ReadReleaseOperation(context context.Context, updateID string) (guestproductreleasemanagerdomain.GuestProductReleaseOperation, bool, error) {
	return service.repository.ReadReleaseOperation(context, updateID)
}

func (service *GuestProductReleaseManagerApplicationService) rollbackAfterTargetFailure(context context.Context, operation guestproductreleasemanagerdomain.GuestProductReleaseOperation, failure *ReleaseManagementFailure) (guestproductreleasemanagerdomain.GuestProductReleaseOperation, error) {
	if !failure.valid() {
		return guestproductreleasemanagerdomain.GuestProductReleaseOperation{}, fmt.Errorf("C59 target release failure is invalid")
	}
	rollback, err := guestproductreleasemanagerdomain.BeginReleaseRollback(operation, service.clock.Now(), failure.Issue)
	if err != nil {
		return guestproductreleasemanagerdomain.GuestProductReleaseOperation{}, err
	}
	if err := service.repository.WriteReleaseOperation(context, rollback); err != nil {
		return guestproductreleasemanagerdomain.GuestProductReleaseOperation{}, fmt.Errorf("persist C59 rollback-applying release operation: %w", err)
	}
	previousTarget := guestproductreleasemanagerdomain.ReleaseReference{ReleaseID: rollback.ExpectedActiveReleaseID, ReleaseDirectory: service.releaseDirectory(rollback.ExpectedActiveReleaseID)}
	if restoreFailure := service.current.ActivateRelease(context, previousTarget); restoreFailure != nil {
		return service.persistTerminalFailure(context, rollback, restoreFailure)
	}
	if restartFailure := service.service.RestartManagedGuestProduct(context); restartFailure != nil {
		return service.persistTerminalFailure(context, rollback, restartFailure)
	}
	if healthFailure := service.health.WaitForGuestProductHealth(context); healthFailure != nil {
		return service.persistTerminalFailure(context, rollback, healthFailure)
	}
	rollback, err = guestproductreleasemanagerdomain.CompleteReleaseRollback(rollback, service.clock.Now())
	if err != nil {
		return guestproductreleasemanagerdomain.GuestProductReleaseOperation{}, err
	}
	if err := service.repository.WriteReleaseOperation(context, rollback); err != nil {
		return guestproductreleasemanagerdomain.GuestProductReleaseOperation{}, fmt.Errorf("persist C59 rolled-back release operation: %w", err)
	}
	return rollback, nil
}

func (service *GuestProductReleaseManagerApplicationService) persistTerminalFailure(context context.Context, operation guestproductreleasemanagerdomain.GuestProductReleaseOperation, failure *ReleaseManagementFailure) (guestproductreleasemanagerdomain.GuestProductReleaseOperation, error) {
	if !failure.valid() {
		return guestproductreleasemanagerdomain.GuestProductReleaseOperation{}, fmt.Errorf("C59 release-management failure is invalid")
	}
	terminal, err := guestproductreleasemanagerdomain.FailReleaseOperation(operation, service.clock.Now(), failure.State, failure.Issue)
	if err != nil {
		return guestproductreleasemanagerdomain.GuestProductReleaseOperation{}, err
	}
	if err := service.repository.WriteReleaseOperation(context, terminal); err != nil {
		return guestproductreleasemanagerdomain.GuestProductReleaseOperation{}, fmt.Errorf("persist C59 terminal release operation: %w", err)
	}
	return terminal, nil
}

func (service *GuestProductReleaseManagerApplicationService) releaseDirectory(releaseID string) string {
	return service.configuration.ReleaseDirectoryRoot + "/" + releaseID
}
