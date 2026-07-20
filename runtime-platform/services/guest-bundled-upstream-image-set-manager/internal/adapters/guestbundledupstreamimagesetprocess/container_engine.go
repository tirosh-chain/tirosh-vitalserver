// Package guestbundledupstreamimagesetprocess owns the narrowly fixed Docker
// process calls for C64. It never calls a shell and never discovers a compose
// project, engine executable, archive path, or health command.
package guestbundledupstreamimagesetprocess

import (
	"context"
	"fmt"
	"os/exec"
	"path/filepath"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-manager/internal/adapters/guestbundledupstreamimagesetfilesystem"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-manager/internal/guestbundledupstreamimagesetmanagerapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-manager/internal/guestbundledupstreamimagesetmanagerdomain"
)

type DockerCLIContainerEngine struct { configuration guestbundledupstreamimagesetmanagerdomain.ManagerConfiguration }

func NewDockerCLIContainerEngine(configuration guestbundledupstreamimagesetmanagerdomain.ManagerConfiguration) (*DockerCLIContainerEngine, error) {
	if err := guestbundledupstreamimagesetmanagerdomain.ValidateManagerConfiguration(configuration); err != nil { return nil, err }
	return &DockerCLIContainerEngine{configuration: configuration}, nil
}

func (engine *DockerCLIContainerEngine) LoadImageSet(context context.Context, imageSetDirectory string) *guestbundledupstreamimagesetmanagerapplication.ImageSetManagementFailure {
	_, archives, err := guestbundledupstreamimagesetfilesystem.ReadStagedImageSetManifest(imageSetDirectory)
	if err != nil { return failed("image-set-manifest-unavailable", err, "guest-image-set-state") }
	for _, archive := range archives {
		if err := exec.CommandContext(context, engine.configuration.ContainerEngineExecutablePath, "load", "--input", filepath.Join(imageSetDirectory, filepath.FromSlash(archive))).Run(); err != nil {
			return classifyCommandFailure(context, "container-image-load-failed", err)
		}
	}
	return nil
}

func (engine *DockerCLIContainerEngine) StartImageSet(context context.Context, imageSetDirectory string) *guestbundledupstreamimagesetmanagerapplication.ImageSetManagementFailure {
	composeFile, _, err := guestbundledupstreamimagesetfilesystem.ReadStagedImageSetManifest(imageSetDirectory)
	if err != nil { return failed("image-set-manifest-unavailable", err, "guest-image-set-state") }
	if err := exec.CommandContext(context, engine.configuration.ContainerEngineExecutablePath, "compose", "--project-name", engine.configuration.ContainerEngineComposeProjectID, "--file", filepath.Join(imageSetDirectory, filepath.FromSlash(composeFile)), "up", "--detach", "--remove-orphans").Run(); err != nil {
		return classifyCommandFailure(context, "container-compose-start-failed", err)
	}
	return nil
}

func classifyCommandFailure(context context.Context, code string, err error) *guestbundledupstreamimagesetmanagerapplication.ImageSetManagementFailure {
	state := guestbundledupstreamimagesetmanagerdomain.OperationStateFailed
	if context.Err() != nil { state = guestbundledupstreamimagesetmanagerdomain.OperationStateUnavailable }
	return &guestbundledupstreamimagesetmanagerapplication.ImageSetManagementFailure{State: state, Issue: guestbundledupstreamimagesetmanagerdomain.Issue{Code: code, Message: fmt.Sprintf("%v", err), Dependency: "container-engine"}}
}
func failed(code string, err error, dependency string) *guestbundledupstreamimagesetmanagerapplication.ImageSetManagementFailure { return &guestbundledupstreamimagesetmanagerapplication.ImageSetManagementFailure{State: guestbundledupstreamimagesetmanagerdomain.OperationStateFailed, Issue: guestbundledupstreamimagesetmanagerdomain.Issue{Code: code, Message: err.Error(), Dependency: dependency}} }

var _ guestbundledupstreamimagesetmanagerapplication.GuestContainerEngine = (*DockerCLIContainerEngine)(nil)
