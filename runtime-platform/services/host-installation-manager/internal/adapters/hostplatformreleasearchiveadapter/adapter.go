// Package hostplatformreleasearchiveadapter translates the filesystem-owned
// candidate record to the application port without exposing it as a Domain
// contract.
package hostplatformreleasearchiveadapter

import (
	"context"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostplatformreleasearchivefilesystem"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostplatformstagedreleaseupdateapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostplatformstagedreleaseupdatedomain"
)

type Adapter struct {
	stager hostplatformreleasearchivefilesystem.FilesystemStager
}

func New() Adapter { return Adapter{stager: hostplatformreleasearchivefilesystem.FilesystemStager{}} }
func (adapter Adapter) Inspect(ctx context.Context, command hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateCommand, artifactPath string) (hostplatformstagedreleaseupdateapplication.InspectedHostPlatformReleaseArchive, error) {
	inspected, err := adapter.stager.InspectHostPlatformReleaseArchive(ctx, command, artifactPath)
	if err != nil {
		return hostplatformstagedreleaseupdateapplication.InspectedHostPlatformReleaseArchive{}, err
	}
	return hostplatformstagedreleaseupdateapplication.InspectedHostPlatformReleaseArchive{Manifest: inspected.Manifest, TemporaryDirectory: inspected.TemporaryDirectory, ReleaseDirectory: inspected.ReleaseDirectory, ServiceDefinitionSources: inspected.ServiceDefinitionSources, OperatorBootstrapSource: inspected.OperatorBootstrapSource}, nil
}
func (adapter Adapter) Persist(inspected hostplatformstagedreleaseupdateapplication.InspectedHostPlatformReleaseArchive, active hostinstallationmanagerdomain.HostProductInstallationManifest, command hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateCommand) (hostplatformstagedreleaseupdatedomain.CandidateHostRelease, error) {
	return adapter.stager.PersistCandidate(hostplatformreleasearchivefilesystem.InspectedReleaseArchive{Manifest: inspected.Manifest, TemporaryDirectory: inspected.TemporaryDirectory, ReleaseDirectory: inspected.ReleaseDirectory, ServiceDefinitionSources: inspected.ServiceDefinitionSources, OperatorBootstrapSource: inspected.OperatorBootstrapSource}, active, command)
}
func (adapter Adapter) Remove(inspected hostplatformstagedreleaseupdateapplication.InspectedHostPlatformReleaseArchive) error {
	return adapter.stager.RemoveInspectedArchive(hostplatformreleasearchivefilesystem.InspectedReleaseArchive{TemporaryDirectory: inspected.TemporaryDirectory})
}
