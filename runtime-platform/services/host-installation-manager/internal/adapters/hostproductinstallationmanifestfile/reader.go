// Package hostproductinstallationmanifestfile owns strict C48 JSON decoding
// from one explicit local file path.
package hostproductinstallationmanifestfile

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

const maximumHostProductInstallationManifestBytes = 1024 * 1024

type HostProductInstallationManifestFileReader struct{}

func (HostProductInstallationManifestFileReader) ReadHostProductInstallationManifest(_ context.Context, path string) (hostinstallationmanagerdomain.HostProductInstallationManifest, error) {
	if path == "" {
		return hostinstallationmanagerdomain.HostProductInstallationManifest{}, fmt.Errorf("Host product installation manifest path is required")
	}
	file, err := os.Open(path)
	if err != nil {
		return hostinstallationmanagerdomain.HostProductInstallationManifest{}, fmt.Errorf("open Host product installation manifest: %w", err)
	}
	defer file.Close()
	reader := io.LimitReader(file, maximumHostProductInstallationManifestBytes+1)
	decoder := json.NewDecoder(reader)
	decoder.DisallowUnknownFields()
	var manifest hostinstallationmanagerdomain.HostProductInstallationManifest
	if err := decoder.Decode(&manifest); err != nil {
		return hostinstallationmanagerdomain.HostProductInstallationManifest{}, fmt.Errorf("decode Host product installation manifest: %w", err)
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		if err == nil {
			return hostinstallationmanagerdomain.HostProductInstallationManifest{}, fmt.Errorf("Host product installation manifest must contain one JSON document")
		}
		return hostinstallationmanagerdomain.HostProductInstallationManifest{}, fmt.Errorf("read Host product installation manifest trailing content: %w", err)
	}
	if err := hostinstallationmanagerdomain.ValidateHostProductInstallationManifest(manifest); err != nil {
		return hostinstallationmanagerdomain.HostProductInstallationManifest{}, fmt.Errorf("validate Host product installation manifest: %w", err)
	}
	return manifest, nil
}
