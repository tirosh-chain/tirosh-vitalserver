// Package guestproductbootstrapvolumeapplication orchestrates one declared
// NoCloud volume effect. It reads explicit Host paths and delegates all
// filesystem-format work to its supplied adapter; it does not own Guest state.
package guestproductbootstrapvolumeapplication

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-bootstrap-volume-composer/internal/guestproductbootstrapvolumeplan"
)

// GuestProductBootstrapVolumeCompositionExecution is the complete C40 Host
// effect input. All three paths must be caller-selected absolute locations.
type GuestProductBootstrapVolumeCompositionExecution struct {
	CompositionPlanPath string
	SourceRoot          string
	OutputVolumePath    string
}

// GuestProductBootstrapVolumeCompositionEffect owns the selected NoCloud
// volume format effect. A different filesystem implementation must implement
// this port explicitly rather than being discovered by command lookup.
type GuestProductBootstrapVolumeCompositionEffect interface {
	ComposeDeclaredGuestProductBootstrapVolume(
		plan guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan,
		sourceRoot string,
		outputVolumePath string,
	) error
}

// ExecuteGuestProductBootstrapVolumeComposition reads and validates C40, then
// invokes one supplied adapter. Decode, path, and adapter errors remain
// failures; none become an empty bootstrap volume.
func ExecuteGuestProductBootstrapVolumeComposition(
	execution GuestProductBootstrapVolumeCompositionExecution,
	effect GuestProductBootstrapVolumeCompositionEffect,
) (string, error) {
	if effect == nil {
		return "", fmt.Errorf("C40 bootstrap volume effect is required")
	}
	if err := requireAbsoluteRegularNonSymlinkFile(execution.CompositionPlanPath, "C40 composition plan"); err != nil {
		return "", err
	}
	if err := requireAbsoluteDirectoryNonSymlink(execution.SourceRoot, "C40 source root"); err != nil {
		return "", err
	}
	if err := requireAbsoluteNewOutputFile(execution.OutputVolumePath, "C40 output volume"); err != nil {
		return "", err
	}
	plan, err := readGuestProductBootstrapVolumeCompositionPlan(execution.CompositionPlanPath)
	if err != nil {
		return "", err
	}
	if err := effect.ComposeDeclaredGuestProductBootstrapVolume(plan, execution.SourceRoot, execution.OutputVolumePath); err != nil {
		return "", err
	}
	return plan.BootstrapID, nil
}

func readGuestProductBootstrapVolumeCompositionPlan(planPath string) (guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan, error) {
	info, err := os.Lstat(planPath)
	if err != nil {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, fmt.Errorf("C40 composition plan cannot be stated: %w", err)
	}
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, fmt.Errorf("C40 composition plan must be a regular non-symlink file")
	}
	if info.Size() > guestproductbootstrapvolumeplan.GuestProductBootstrapPlanMaximumBytes {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, fmt.Errorf("C40 composition plan exceeds %d bytes", guestproductbootstrapvolumeplan.GuestProductBootstrapPlanMaximumBytes)
	}
	file, err := os.Open(planPath)
	if err != nil {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, fmt.Errorf("C40 composition plan cannot be opened: %w", err)
	}
	defer file.Close()
	decoder := json.NewDecoder(io.LimitReader(file, guestproductbootstrapvolumeplan.GuestProductBootstrapPlanMaximumBytes+1))
	decoder.DisallowUnknownFields()
	var plan guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan
	if err := decoder.Decode(&plan); err != nil {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, fmt.Errorf("C40 composition plan JSON cannot be decoded: %w", err)
	}
	var trailingValue any
	if err := decoder.Decode(&trailingValue); err != io.EOF {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, fmt.Errorf("C40 composition plan must contain one JSON object")
	}
	if err := guestproductbootstrapvolumeplan.ValidateGuestProductBootstrapVolumeCompositionPlan(plan); err != nil {
		return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{}, err
	}
	return plan, nil
}

func requireAbsoluteRegularNonSymlinkFile(value string, role string) error {
	if !filepath.IsAbs(value) {
		return fmt.Errorf("%s path must be absolute", role)
	}
	info, err := os.Lstat(value)
	if err != nil {
		return fmt.Errorf("%s cannot be stated: %w", role, err)
	}
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("%s must be a regular non-symlink file", role)
	}
	return nil
}

func requireAbsoluteDirectoryNonSymlink(value string, role string) error {
	if !filepath.IsAbs(value) {
		return fmt.Errorf("%s path must be absolute", role)
	}
	info, err := os.Lstat(value)
	if err != nil {
		return fmt.Errorf("%s cannot be stated: %w", role, err)
	}
	if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("%s must be a directory non-symlink", role)
	}
	return nil
}

func requireAbsoluteNewOutputFile(value string, role string) error {
	if !filepath.IsAbs(value) {
		return fmt.Errorf("%s path must be absolute", role)
	}
	if _, err := os.Lstat(value); err == nil {
		return fmt.Errorf("%s must not already exist", role)
	} else if !os.IsNotExist(err) {
		return fmt.Errorf("%s cannot be stated: %w", role, err)
	}
	parent := filepath.Dir(value)
	info, err := os.Lstat(parent)
	if err != nil {
		return fmt.Errorf("%s parent cannot be stated: %w", role, err)
	}
	if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("%s parent must be a directory non-symlink", role)
	}
	return nil
}
