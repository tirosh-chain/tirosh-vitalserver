package guestbundledupstreamimagesetmanagerapplication

import (
	"context"
	"io"
	"strings"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-manager/internal/guestbundledupstreamimagesetmanagerdomain"
)

type fixedClock struct{}
func (fixedClock) Now() string { return "2026-07-20T00:00:00Z" }

type memoryOperations struct{ values map[string]guestbundledupstreamimagesetmanagerdomain.ImageSetOperation }
func (repository *memoryOperations) ReadImageSetOperation(_ context.Context, id string) (guestbundledupstreamimagesetmanagerdomain.ImageSetOperation, bool, error) { value, found := repository.values[id]; return value, found, nil }
func (repository *memoryOperations) WriteImageSetOperation(_ context.Context, operation guestbundledupstreamimagesetmanagerdomain.ImageSetOperation) error { repository.values[operation.UpdateID] = operation; return nil }

type stagedArchive struct{}
func (stagedArchive) StageImageSetArchive(_ context.Context, _ guestbundledupstreamimagesetmanagerdomain.ImageSetUpdateCommand, _ io.Reader) (string, *ImageSetManagementFailure) { return "/var/lib/vitalserver/bundled-upstream-image-sets/image-sets/bundled-upstream-030", nil }

type activeImageSet struct{ value guestbundledupstreamimagesetmanagerdomain.ActiveImageSetSelection; readFailure, writeFailure *ImageSetManagementFailure }
func (state *activeImageSet) ReadActiveImageSet(context.Context) (guestbundledupstreamimagesetmanagerdomain.ActiveImageSetSelection, *ImageSetManagementFailure) { return state.value, state.readFailure }
func (state *activeImageSet) WriteActiveImageSet(_ context.Context, selection guestbundledupstreamimagesetmanagerdomain.ActiveImageSetSelection) *ImageSetManagementFailure { if state.writeFailure != nil { return state.writeFailure }; state.value = selection; return nil }

type engine struct{ loadFailure, startFailure *ImageSetManagementFailure; loaded, started bool }
func (value *engine) LoadImageSet(context.Context, string) *ImageSetManagementFailure { value.loaded = true; return value.loadFailure }
func (value *engine) StartImageSet(context.Context, string) *ImageSetManagementFailure { value.started = true; return value.startFailure }

func TestApplyUsesC64OwnedActiveStateAsItsCompareAndSwap(t *testing.T) {
	repository := &memoryOperations{values: map[string]guestbundledupstreamimagesetmanagerdomain.ImageSetOperation{}}
	state := &activeImageSet{value: guestbundledupstreamimagesetmanagerdomain.ActiveImageSetSelection{State: guestbundledupstreamimagesetmanagerdomain.SelectionActive, ImageSetID: "bundled-upstream-020"}}
	containerEngine := &engine{}
	application, err := NewImageSetManagerApplicationService(configuration(), repository, stagedArchive{}, state, containerEngine, fixedClock{})
	if err != nil { t.Fatal(err) }
	operation, err := application.ApplyImageSetUpdate(context.Background(), command(), strings.NewReader("archive"))
	if err != nil { t.Fatal(err) }
	if operation.State != guestbundledupstreamimagesetmanagerdomain.OperationStateSucceeded || state.value.ImageSetID != "bundled-upstream-030" || !containerEngine.loaded || !containerEngine.started { t.Fatalf("operation=%+v state=%+v engine=%+v", operation, state.value, containerEngine) }
}

func TestActiveStateMismatchBecomesARecordedFailure(t *testing.T) {
	repository := &memoryOperations{values: map[string]guestbundledupstreamimagesetmanagerdomain.ImageSetOperation{}}
	state := &activeImageSet{value: guestbundledupstreamimagesetmanagerdomain.ActiveImageSetSelection{State: guestbundledupstreamimagesetmanagerdomain.SelectionUnprovisioned}}
	application, err := NewImageSetManagerApplicationService(configuration(), repository, stagedArchive{}, state, &engine{}, fixedClock{})
	if err != nil { t.Fatal(err) }
	operation, err := application.ApplyImageSetUpdate(context.Background(), command(), strings.NewReader("archive"))
	if err != nil { t.Fatal(err) }
	if operation.State != guestbundledupstreamimagesetmanagerdomain.OperationStateFailed || operation.Issue == nil || operation.Issue.Code != "active-image-set-mismatch" { t.Fatalf("operation=%+v", operation) }
}

func configuration() guestbundledupstreamimagesetmanagerdomain.ManagerConfiguration { return guestbundledupstreamimagesetmanagerdomain.ManagerConfiguration{ManagerID: "bundled-upstream-image-set-manager", StateDirectory: "/var/lib/vitalserver/bundled-upstream-image-sets", StagingDirectory: "/var/lib/vitalserver/bundled-upstream-image-sets/staging", StateDirectoryMode: "0700", MaximumImageSetArtifactBytes: 1024 * 1024, ContainerEngineExecutablePath: "/usr/bin/docker", ContainerEngineComposeProjectID: "vitalserver-bundled-upstream"} }
func command() guestbundledupstreamimagesetmanagerdomain.ImageSetUpdateCommand { return guestbundledupstreamimagesetmanagerdomain.ImageSetUpdateCommand{SchemaVersion: "v1", UpdateID: "bundled-upstream-update-030", ExpectedActiveImageSet: guestbundledupstreamimagesetmanagerdomain.ActiveImageSetSelection{State: "active", ImageSetID: "bundled-upstream-020"}, TargetImageSet: guestbundledupstreamimagesetmanagerdomain.ImageSetTarget{ImageSetID: "bundled-upstream-030", Artifact: guestbundledupstreamimagesetmanagerdomain.ImageSetArtifact{SHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", SizeBytes: 200, MediaType: guestbundledupstreamimagesetmanagerdomain.ImageSetArchiveMediaType}}, RequestedAt: "2026-07-20T00:00:00Z"} }
