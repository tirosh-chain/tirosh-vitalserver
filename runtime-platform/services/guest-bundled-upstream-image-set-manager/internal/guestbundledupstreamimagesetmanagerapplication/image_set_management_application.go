// Package guestbundledupstreamimagesetmanagerapplication orchestrates the
// C64 state machine through explicit Guest-owned ports.
package guestbundledupstreamimagesetmanagerapplication

import (
	"context"
	"fmt"
	"io"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-manager/internal/guestbundledupstreamimagesetmanagerdomain"
)

type ImageSetOperationRepository interface {
	ReadImageSetOperation(context.Context, string) (guestbundledupstreamimagesetmanagerdomain.ImageSetOperation, bool, error)
	WriteImageSetOperation(context.Context, guestbundledupstreamimagesetmanagerdomain.ImageSetOperation) error
}

type ImageSetArchiveStager interface {
	StageImageSetArchive(context.Context, guestbundledupstreamimagesetmanagerdomain.ImageSetUpdateCommand, io.Reader) (string, *ImageSetManagementFailure)
}

type ActiveImageSetRepository interface {
	ReadActiveImageSet(context.Context) (guestbundledupstreamimagesetmanagerdomain.ActiveImageSetSelection, *ImageSetManagementFailure)
	WriteActiveImageSet(context.Context, guestbundledupstreamimagesetmanagerdomain.ActiveImageSetSelection) *ImageSetManagementFailure
}

type GuestContainerEngine interface {
	LoadImageSet(context.Context, string) *ImageSetManagementFailure
	StartImageSet(context.Context, string) *ImageSetManagementFailure
}

type Clock interface{ Now() string }

// ImageSetManagementFailure preserves the adapter's own classification.
// It deliberately does not turn a Docker command failure into a generic
// update failure or treat a missing state file as an active selection.
type ImageSetManagementFailure struct {
	State string
	Issue guestbundledupstreamimagesetmanagerdomain.Issue
}

func (failure *ImageSetManagementFailure) valid() bool {
	return failure != nil && (failure.State == guestbundledupstreamimagesetmanagerdomain.OperationStateFailed || failure.State == guestbundledupstreamimagesetmanagerdomain.OperationStateUnavailable) && failure.Issue.Code != "" && failure.Issue.Message != ""
}

type ImageSetManagerApplicationService struct {
	configuration guestbundledupstreamimagesetmanagerdomain.ManagerConfiguration
	repository    ImageSetOperationRepository
	stager        ImageSetArchiveStager
	active        ActiveImageSetRepository
	engine        GuestContainerEngine
	clock         Clock
}

func NewImageSetManagerApplicationService(
	configuration guestbundledupstreamimagesetmanagerdomain.ManagerConfiguration,
	repository ImageSetOperationRepository,
	stager ImageSetArchiveStager,
	active ActiveImageSetRepository,
	engine GuestContainerEngine,
	clock Clock,
) (*ImageSetManagerApplicationService, error) {
	if err := guestbundledupstreamimagesetmanagerdomain.ValidateManagerConfiguration(configuration); err != nil {
		return nil, err
	}
	if repository == nil || stager == nil || active == nil || engine == nil || clock == nil {
		return nil, fmt.Errorf("C64 repository, stager, active image-set repository, container engine, and clock are required")
	}
	return &ImageSetManagerApplicationService{configuration: configuration, repository: repository, stager: stager, active: active, engine: engine, clock: clock}, nil
}

// ApplyImageSetUpdate provides a compare-and-swap on the only Guest-owned
// active image-set state. It intentionally does not inspect existing Docker
// containers; the C64 manager's durable state is the sole state authority.
func (service *ImageSetManagerApplicationService) ApplyImageSetUpdate(
	context context.Context,
	command guestbundledupstreamimagesetmanagerdomain.ImageSetUpdateCommand,
	archive io.Reader,
) (guestbundledupstreamimagesetmanagerdomain.ImageSetOperation, error) {
	if archive == nil {
		return guestbundledupstreamimagesetmanagerdomain.ImageSetOperation{}, fmt.Errorf("C64 image-set archive is required")
	}
	if err := guestbundledupstreamimagesetmanagerdomain.ValidateImageSetUpdateCommand(service.configuration, command); err != nil {
		return guestbundledupstreamimagesetmanagerdomain.ImageSetOperation{}, err
	}
	existing, found, err := service.repository.ReadImageSetOperation(context, command.UpdateID)
	if err != nil {
		return guestbundledupstreamimagesetmanagerdomain.ImageSetOperation{}, fmt.Errorf("read C64 image-set operation: %w", err)
	}
	if found {
		if !guestbundledupstreamimagesetmanagerdomain.SameImageSetUpdateCommand(existing, command) {
			return guestbundledupstreamimagesetmanagerdomain.ImageSetOperation{}, fmt.Errorf("C64 update id already belongs to a different image-set command")
		}
		return existing, nil
	}
	selection, selectionFailure := service.active.ReadActiveImageSet(context)
	if selectionFailure != nil {
		return service.persistTerminalFailure(context, guestbundledupstreamimagesetmanagerdomain.NewImageSetOperation(command, service.clock.Now()), selectionFailure)
	}
	if selection != command.ExpectedActiveImageSet {
		return service.persistTerminalFailure(context, guestbundledupstreamimagesetmanagerdomain.NewImageSetOperation(command, service.clock.Now()), &ImageSetManagementFailure{State: guestbundledupstreamimagesetmanagerdomain.OperationStateFailed, Issue: guestbundledupstreamimagesetmanagerdomain.Issue{Code: "active-image-set-mismatch", Message: "declared expected active image set does not match Guest image-set state", Dependency: "guest-image-set-state"}})
	}
	operation := guestbundledupstreamimagesetmanagerdomain.NewImageSetOperation(command, service.clock.Now())
	if err := service.repository.WriteImageSetOperation(context, operation); err != nil {
		return guestbundledupstreamimagesetmanagerdomain.ImageSetOperation{}, fmt.Errorf("persist C64 received image-set operation: %w", err)
	}
	imageSetDirectory, stageFailure := service.stager.StageImageSetArchive(context, command, archive)
	if stageFailure != nil {
		return service.persistTerminalFailure(context, operation, stageFailure)
	}
	if operation, err = guestbundledupstreamimagesetmanagerdomain.MarkImageSetStaged(operation, service.clock.Now()); err != nil {
		return guestbundledupstreamimagesetmanagerdomain.ImageSetOperation{}, err
	}
	if err := service.repository.WriteImageSetOperation(context, operation); err != nil {
		return guestbundledupstreamimagesetmanagerdomain.ImageSetOperation{}, fmt.Errorf("persist C64 staged image-set operation: %w", err)
	}
	if operation, err = guestbundledupstreamimagesetmanagerdomain.BeginImageLoad(operation, service.clock.Now()); err != nil {
		return guestbundledupstreamimagesetmanagerdomain.ImageSetOperation{}, err
	}
	if err := service.repository.WriteImageSetOperation(context, operation); err != nil {
		return guestbundledupstreamimagesetmanagerdomain.ImageSetOperation{}, fmt.Errorf("persist C64 loading-images operation: %w", err)
	}
	if failure := service.engine.LoadImageSet(context, imageSetDirectory); failure != nil {
		return service.persistTerminalFailure(context, operation, failure)
	}
	if operation, err = guestbundledupstreamimagesetmanagerdomain.BeginContainerStart(operation, service.clock.Now()); err != nil {
		return guestbundledupstreamimagesetmanagerdomain.ImageSetOperation{}, err
	}
	if err := service.repository.WriteImageSetOperation(context, operation); err != nil {
		return guestbundledupstreamimagesetmanagerdomain.ImageSetOperation{}, fmt.Errorf("persist C64 starting-containers operation: %w", err)
	}
	if failure := service.engine.StartImageSet(context, imageSetDirectory); failure != nil {
		return service.persistTerminalFailure(context, operation, failure)
	}
	active := guestbundledupstreamimagesetmanagerdomain.ActiveImageSetSelection{State: guestbundledupstreamimagesetmanagerdomain.SelectionActive, ImageSetID: command.TargetImageSet.ImageSetID}
	if failure := service.active.WriteActiveImageSet(context, active); failure != nil {
		return service.persistTerminalFailure(context, operation, failure)
	}
	if operation, err = guestbundledupstreamimagesetmanagerdomain.CompleteImageSetActivation(operation, service.clock.Now()); err != nil {
		return guestbundledupstreamimagesetmanagerdomain.ImageSetOperation{}, err
	}
	if err := service.repository.WriteImageSetOperation(context, operation); err != nil {
		return guestbundledupstreamimagesetmanagerdomain.ImageSetOperation{}, fmt.Errorf("persist C64 succeeded image-set operation: %w", err)
	}
	return operation, nil
}

func (service *ImageSetManagerApplicationService) ReadImageSetOperation(context context.Context, updateID string) (guestbundledupstreamimagesetmanagerdomain.ImageSetOperation, bool, error) {
	return service.repository.ReadImageSetOperation(context, updateID)
}

func (service *ImageSetManagerApplicationService) persistTerminalFailure(context context.Context, operation guestbundledupstreamimagesetmanagerdomain.ImageSetOperation, failure *ImageSetManagementFailure) (guestbundledupstreamimagesetmanagerdomain.ImageSetOperation, error) {
	if !failure.valid() {
		return guestbundledupstreamimagesetmanagerdomain.ImageSetOperation{}, fmt.Errorf("C64 image-set-management failure is invalid")
	}
	terminal, err := guestbundledupstreamimagesetmanagerdomain.FailImageSetOperation(operation, service.clock.Now(), failure.State, failure.Issue)
	if err != nil {
		return guestbundledupstreamimagesetmanagerdomain.ImageSetOperation{}, err
	}
	if err := service.repository.WriteImageSetOperation(context, terminal); err != nil {
		return guestbundledupstreamimagesetmanagerdomain.ImageSetOperation{}, fmt.Errorf("persist C64 terminal image-set operation: %w", err)
	}
	return terminal, nil
}
