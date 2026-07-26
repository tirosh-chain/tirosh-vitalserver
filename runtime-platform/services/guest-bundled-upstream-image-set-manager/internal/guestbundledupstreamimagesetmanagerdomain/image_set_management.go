// Package guestbundledupstreamimagesetmanagerdomain defines the pure C64
// image-set state machine. It does not read Guest files, invoke Docker, or
// infer an active image set from a container-engine listing.
package guestbundledupstreamimagesetmanagerdomain

import (
	"fmt"
	"path"
	"regexp"
	"strings"
)

const SchemaVersion = "v1"

const (
	ImageSetArchiveMediaType = "application/vnd.tirosh.vitalserver.bundled-upstream-image-set+tar+gzip"
	SelectionUnprovisioned   = "unprovisioned"
	SelectionActive          = "active"

	OperationStateReceived           = "received"
	OperationStateStaged             = "staged"
	OperationStateLoadingImages      = "loading-images"
	OperationStateStartingContainers = "starting-containers"
	OperationStateSucceeded          = "succeeded"
	OperationStateFailed             = "failed"
	OperationStateUnavailable        = "unavailable"
)

var (
	identifierPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$`)
	sha256Pattern     = regexp.MustCompile(`^[a-f0-9]{64}$`)
)

type Issue struct {
	Code       string `json:"code"`
	Message    string `json:"message"`
	Dependency string `json:"dependency,omitempty"`
}

// ActiveImageSetSelection is an intentional state value. It is not a
// convenience conversion of an unreadable state document into "unprovisioned".
type ActiveImageSetSelection struct {
	State      string `json:"state"`
	ImageSetID string `json:"imageSetId,omitempty"`
}

type ImageSetArtifact struct {
	SHA256    string `json:"sha256"`
	SizeBytes int64  `json:"sizeBytes"`
	MediaType string `json:"mediaType"`
}

type ImageSetTarget struct {
	ImageSetID string           `json:"imageSetId"`
	Artifact   ImageSetArtifact `json:"artifact"`
}

type ImageSetUpdateCommand struct {
	SchemaVersion          string                  `json:"schemaVersion"`
	UpdateID               string                  `json:"updateId"`
	ExpectedActiveImageSet ActiveImageSetSelection `json:"expectedActiveImageSet"`
	TargetImageSet         ImageSetTarget          `json:"targetImageSet"`
	RequestedAt            string                  `json:"requestedAt"`
}

type ImageSetOperation struct {
	SchemaVersion          string                   `json:"schemaVersion"`
	UpdateID               string                   `json:"updateId"`
	ExpectedActiveImageSet ActiveImageSetSelection  `json:"expectedActiveImageSet"`
	TargetImageSet         ImageSetTarget           `json:"targetImageSet"`
	State                  string                   `json:"state"`
	ActiveImageSet         *ActiveImageSetSelection `json:"activeImageSet,omitempty"`
	ObservedAt             string                   `json:"observedAt"`
	Issue                  *Issue                   `json:"issue,omitempty"`
}

type ManagerConfiguration struct {
	ManagerID                       string
	StateDirectory                  string
	StagingDirectory                string
	StateDirectoryMode              string
	MaximumImageSetArtifactBytes    int64
	ContainerEngineExecutablePath   string
	ContainerEngineComposeProjectID string
}

type LoopbackListener struct {
	BindHost string
	Port     int
}

func ValidateLoopbackListener(listener LoopbackListener) error {
	if listener.BindHost != "127.0.0.1" || listener.Port < 1 || listener.Port > 65535 {
		return fmt.Errorf("C64 bundled upstream image-set manager listener must be an explicit loopback address and port")
	}
	return nil
}

func ValidateManagerConfiguration(configuration ManagerConfiguration) error {
	if !validIdentifier(configuration.ManagerID) ||
		!safeAbsolutePath(configuration.StateDirectory) ||
		!safeAbsolutePath(configuration.StagingDirectory) ||
		configuration.StateDirectoryMode != "0700" ||
		configuration.MaximumImageSetArtifactBytes < 1 ||
		!safeAbsolutePath(configuration.ContainerEngineExecutablePath) ||
		!validIdentifier(configuration.ContainerEngineComposeProjectID) {
		return fmt.Errorf("C64 bundled upstream image-set manager configuration is invalid")
	}
	if configuration.StateDirectory == configuration.StagingDirectory || path.Dir(configuration.StagingDirectory) != configuration.StateDirectory {
		return fmt.Errorf("C64 state and staging directories must be distinct declared ownership roots")
	}
	return nil
}

func ValidateActiveImageSetSelection(selection ActiveImageSetSelection) error {
	switch selection.State {
	case SelectionUnprovisioned:
		if selection.ImageSetID != "" {
			return fmt.Errorf("C64 unprovisioned image-set selection cannot name an image set")
		}
	case SelectionActive:
		if !validIdentifier(selection.ImageSetID) {
			return fmt.Errorf("C64 active image-set selection requires an image set id")
		}
	default:
		return fmt.Errorf("C64 image-set selection state is unsupported")
	}
	return nil
}

func ValidateImageSetUpdateCommand(configuration ManagerConfiguration, command ImageSetUpdateCommand) error {
	if err := ValidateManagerConfiguration(configuration); err != nil {
		return err
	}
	if command.SchemaVersion != SchemaVersion || !validIdentifier(command.UpdateID) || command.RequestedAt == "" ||
		ValidateActiveImageSetSelection(command.ExpectedActiveImageSet) != nil ||
		!validIdentifier(command.TargetImageSet.ImageSetID) ||
		!sha256Pattern.MatchString(command.TargetImageSet.Artifact.SHA256) ||
		command.TargetImageSet.Artifact.SizeBytes < 1 || command.TargetImageSet.Artifact.SizeBytes > configuration.MaximumImageSetArtifactBytes ||
		command.TargetImageSet.Artifact.MediaType != ImageSetArchiveMediaType {
		return fmt.Errorf("C64 bundled upstream image-set update command is invalid")
	}
	if command.ExpectedActiveImageSet.State == SelectionActive && command.ExpectedActiveImageSet.ImageSetID == command.TargetImageSet.ImageSetID {
		return fmt.Errorf("C64 image-set update target cannot equal its expected active image set")
	}
	return nil
}

func ValidateImageSetOperation(configuration ManagerConfiguration, operation ImageSetOperation) error {
	command := ImageSetUpdateCommand{
		SchemaVersion: operation.SchemaVersion, UpdateID: operation.UpdateID,
		ExpectedActiveImageSet: operation.ExpectedActiveImageSet, TargetImageSet: operation.TargetImageSet,
		RequestedAt: operation.ObservedAt,
	}
	if err := ValidateImageSetUpdateCommand(configuration, command); err != nil || operation.ObservedAt == "" {
		return fmt.Errorf("C64 image-set operation identity is invalid")
	}
	switch operation.State {
	case OperationStateReceived, OperationStateStaged, OperationStateLoadingImages, OperationStateStartingContainers:
		if operation.ActiveImageSet != nil || operation.Issue != nil {
			return fmt.Errorf("C64 in-progress image-set operation cannot claim an outcome")
		}
	case OperationStateSucceeded:
		if operation.ActiveImageSet == nil || operation.ActiveImageSet.State != SelectionActive || operation.ActiveImageSet.ImageSetID != operation.TargetImageSet.ImageSetID || operation.Issue != nil {
			return fmt.Errorf("C64 succeeded image-set operation must name exactly its target active image set")
		}
	case OperationStateFailed, OperationStateUnavailable:
		if operation.ActiveImageSet != nil || !validIssue(operation.Issue) {
			return fmt.Errorf("C64 failed or unavailable image-set operation requires an issue and no active-image claim")
		}
	default:
		return fmt.Errorf("C64 image-set operation state is unsupported")
	}
	return nil
}

func NewImageSetOperation(command ImageSetUpdateCommand, observedAt string) ImageSetOperation {
	return ImageSetOperation{SchemaVersion: SchemaVersion, UpdateID: command.UpdateID, ExpectedActiveImageSet: command.ExpectedActiveImageSet, TargetImageSet: command.TargetImageSet, State: OperationStateReceived, ObservedAt: observedAt}
}

func MarkImageSetStaged(operation ImageSetOperation, observedAt string) (ImageSetOperation, error) {
	return transition(operation, OperationStateReceived, OperationStateStaged, observedAt)
}

func BeginImageLoad(operation ImageSetOperation, observedAt string) (ImageSetOperation, error) {
	return transition(operation, OperationStateStaged, OperationStateLoadingImages, observedAt)
}

func BeginContainerStart(operation ImageSetOperation, observedAt string) (ImageSetOperation, error) {
	return transition(operation, OperationStateLoadingImages, OperationStateStartingContainers, observedAt)
}

func CompleteImageSetActivation(operation ImageSetOperation, observedAt string) (ImageSetOperation, error) {
	if operation.State != OperationStateStartingContainers || observedAt == "" {
		return ImageSetOperation{}, fmt.Errorf("C64 cannot complete image-set activation from %q", operation.State)
	}
	active := ActiveImageSetSelection{State: SelectionActive, ImageSetID: operation.TargetImageSet.ImageSetID}
	operation.State = OperationStateSucceeded
	operation.ActiveImageSet = &active
	operation.ObservedAt = observedAt
	return operation, nil
}

func FailImageSetOperation(operation ImageSetOperation, observedAt string, state string, issue Issue) (ImageSetOperation, error) {
	if observedAt == "" || !validIssue(&issue) || (state != OperationStateFailed && state != OperationStateUnavailable) {
		return ImageSetOperation{}, fmt.Errorf("C64 terminal image-set failure is invalid")
	}
	switch operation.State {
	case OperationStateReceived, OperationStateStaged, OperationStateLoadingImages, OperationStateStartingContainers:
		operation.State = state
		operation.ActiveImageSet = nil
		operation.ObservedAt = observedAt
		operation.Issue = &issue
		return operation, nil
	default:
		return ImageSetOperation{}, fmt.Errorf("C64 terminal image-set failure cannot replace a terminal operation")
	}
}

func SameImageSetUpdateCommand(operation ImageSetOperation, command ImageSetUpdateCommand) bool {
	return operation.UpdateID == command.UpdateID && operation.ExpectedActiveImageSet == command.ExpectedActiveImageSet && operation.TargetImageSet == command.TargetImageSet
}

func transition(operation ImageSetOperation, expected string, next string, observedAt string) (ImageSetOperation, error) {
	if operation.State != expected || observedAt == "" {
		return ImageSetOperation{}, fmt.Errorf("C64 invalid image-set operation transition from %q to %q", operation.State, next)
	}
	operation.State = next
	operation.ObservedAt = observedAt
	return operation, nil
}

func validIdentifier(value string) bool { return identifierPattern.MatchString(value) }

func safeAbsolutePath(value string) bool {
	return len(value) > 1 && strings.HasPrefix(value, "/") && path.Clean(value) == value && !strings.Contains(value, "..")
}

func validIssue(issue *Issue) bool { return issue != nil && validIdentifier(issue.Code) && issue.Message != "" }
