package nativeproviderbridge

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// NativeGuestMachineProvisioningConfiguration is C62 as consumed by the one
// selected native provider. It is desired Host deployment input, never Host
// lifecycle state. C63 is the separate provider-owned persistence boundary.
type NativeGuestMachineProvisioningConfiguration struct {
	SchemaVersion           string                      `json:"schemaVersion"`
	ConfigurationID         string                      `json:"configurationId"`
	ProviderKind            string                      `json:"providerKind"`
	ProviderID              string                      `json:"providerId"`
	GuestArchitecture       string                      `json:"guestArchitecture"`
	GuestMachine            NativeGuestMachine          `json:"guestMachine"`
	ReleaseArtifacts        NativeGuestReleaseArtifacts `json:"releaseArtifacts"`
	RuntimeStorage          NativeGuestRuntimeStorage   `json:"runtimeStorage"`
	Native                  NativeGuestNativeProvider   `json:"native"`
	ProvisioningReceiptPath string                      `json:"provisioningReceiptPath"`
}

type NativeGuestMachine struct {
	MachineID  string `json:"machineId"`
	CPUCount   int    `json:"cpuCount"`
	MemoryMiB  int    `json:"memoryMiB"`
	MACAddress string `json:"macAddress"`
}

type NativeGuestReleaseArtifacts struct {
	NativeGuestArtifactManifest NativeGuestArtifactManifestSource `json:"nativeGuestArtifactManifest"`
	BootableGuestDisk           NativeGuestArtifact               `json:"bootableGuestDisk"`
	GuestProductBootstrapVolume NativeGuestArtifact               `json:"guestProductBootstrapVolume"`
}

// NativeGuestArtifactManifestSource identifies the C65 compiler output that
// is allowed to describe C62's two immutable raw Guest files. It is a Host
// path only; the provider must verify both this file identity and its decoded
// C65 contents before it may create mutable native runtime storage.
type NativeGuestArtifactManifestSource struct {
	SourcePath string `json:"sourcePath"`
	SizeBytes  int64  `json:"sizeBytes"`
	SHA256     string `json:"sha256"`
}

type NativeGuestArtifact struct {
	ID                 string `json:"id"`
	SourcePath         string `json:"sourcePath"`
	SizeBytes          int64  `json:"sizeBytes"`
	SHA256             string `json:"sha256"`
	StorageImageFormat string `json:"storageImageFormat"`
}

type NativeGuestRuntimeStorage struct {
	RootDiskPath                 string `json:"rootDiskPath"`
	BootstrapVolumePath          string `json:"bootstrapVolumePath"`
	ExistingRuntimeStoragePolicy string `json:"existingRuntimeStoragePolicy"`
}

// NativeGuestNativeProvider is intentionally a flat decoded shape. Validate
// rejects properties belonging to the other provider, so an adapter cannot
// silently consume a cross-platform setting.
type NativeGuestNativeProvider struct {
	Kind                           string `json:"kind"`
	ImageConverterExecutablePath   string `json:"imageConverterExecutablePath"`
	LibvirtExecutablePath          string `json:"libvirtExecutablePath"`
	EmulatorExecutablePath         string `json:"emulatorExecutablePath"`
	UEFILoaderPath                 string `json:"uefiLoaderPath"`
	UEFINvramTemplatePath          string `json:"uefiNvramTemplatePath"`
	UEFINvramPath                  string `json:"uefiNvramPath"`
	LibvirtNetworkName             string `json:"libvirtNetworkName"`
	HyperVPowerShellExecutablePath string `json:"hyperVPowerShellExecutablePath"`
	VirtualSwitchName              string `json:"virtualSwitchName"`
	RuntimeImageFormat             string `json:"runtimeImageFormat"`
}

// NativeGuestMachineProvisioningReceipt is C63. Its existence only allows
// C62's explicit retained-storage policy; it is not a Guest boot/readiness or
// package-installation result.
type NativeGuestMachineProvisioningReceipt struct {
	SchemaVersion       string                             `json:"schemaVersion"`
	ConfigurationID     string                             `json:"configurationId"`
	ConfigurationSHA256 string                             `json:"configurationSHA256"`
	ProviderKind        string                             `json:"providerKind"`
	ProviderID          string                             `json:"providerId"`
	MachineID           string                             `json:"machineId"`
	GuestArchitecture   string                             `json:"guestArchitecture"`
	ReleaseArtifacts    NativeGuestReceiptReleaseArtifacts `json:"releaseArtifacts"`
	RuntimeStorage      NativeGuestReceiptRuntimeStorage   `json:"runtimeStorage"`
	CompletedAt         string                             `json:"completedAt"`
}

type NativeGuestReceiptReleaseArtifacts struct {
	NativeGuestArtifactManifest NativeGuestArtifactManifestIdentity `json:"nativeGuestArtifactManifest"`
	BootableGuestDisk           NativeGuestArtifactIdentity         `json:"bootableGuestDisk"`
	GuestProductBootstrapVolume NativeGuestArtifactIdentity         `json:"guestProductBootstrapVolume"`
}

// NativeGuestArtifactManifestIdentity is C63's durable correlation to the
// verified C65 release set, rather than a mutable Host source path.
type NativeGuestArtifactManifestIdentity struct {
	ArtifactSetID string `json:"artifactSetId"`
	SizeBytes     int64  `json:"sizeBytes"`
	SHA256        string `json:"sha256"`
}

type NativeGuestArtifactIdentity struct {
	ID                 string `json:"id"`
	SizeBytes          int64  `json:"sizeBytes"`
	SHA256             string `json:"sha256"`
	StorageImageFormat string `json:"storageImageFormat"`
}

type NativeGuestReceiptRuntimeStorage struct {
	RootDiskPath        string `json:"rootDiskPath"`
	BootstrapVolumePath string `json:"bootstrapVolumePath"`
	RuntimeImageFormat  string `json:"runtimeImageFormat"`
}

// NativeGuestArtifactManifest is the strict C65 compiler output consumed by
// the native Host provisioner. It is deliberately local to this adapter: C65
// is not Host state and it does not claim a Guest boot/readiness outcome.
type NativeGuestArtifactManifest struct {
	SchemaVersion  string                              `json:"schemaVersion"`
	ArtifactSetID  string                              `json:"artifactSetId"`
	Architecture   string                              `json:"architecture"`
	StorageDevices []NativeGuestArtifactManifestDevice `json:"storageDevices"`
}

type NativeGuestArtifactManifestDevice struct {
	ID                    string  `json:"id"`
	Role                  string  `json:"role"`
	StorageImageFormat    string  `json:"storageImageFormat"`
	GuestVolumeFileSystem *string `json:"guestVolumeFileSystem,omitempty"`
	SizeBytes             int64   `json:"sizeBytes"`
	SHA256                string  `json:"sha256"`
}

type NativeGuestMachineProvisioningResult struct {
	Receipt  NativeGuestMachineProvisioningReceipt
	Retained bool
}

var nativeGuestMachineIdentifier = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$`)
var nativeGuestMachineMACAddress = regexp.MustCompile(`^[0-9A-Fa-f][02468AaCcEe](:[0-9A-Fa-f]{2}){5}$`)
var nativeGuestMachineSHA256 = regexp.MustCompile(`^[a-f0-9]{64}$`)
var nativeGuestMachineWindowsPath = regexp.MustCompile(`^[A-Za-z]:[\\/].*$`)

// NativeGuestMachineProvisioningConfigurationUnavailableError preserves a
// Host filesystem/permission dependency failure as unavailable configuration.
// It must not be treated as an empty external-machine selection.
type NativeGuestMachineProvisioningConfigurationUnavailableError struct{ reason string }

func (failure NativeGuestMachineProvisioningConfigurationUnavailableError) Error() string {
	return "C62 configuration is unavailable: " + failure.reason
}

// NativeGuestMachineProvisioningConfigurationInvalidError preserves malformed
// or semantically incomplete desired configuration separately from absence.
type NativeGuestMachineProvisioningConfigurationInvalidError struct{ reason string }

func (failure NativeGuestMachineProvisioningConfigurationInvalidError) Error() string {
	return "C62 configuration is invalid: " + failure.reason
}

// LoadNativeGuestMachineProvisioningConfiguration preserves unavailable,
// invalid, and decoded desired configuration separately. It does not create a
// directory, a VM, or a receipt when C62 cannot be read.
func LoadNativeGuestMachineProvisioningConfiguration(path string) (NativeGuestMachineProvisioningConfiguration, []byte, error) {
	if !isSafeNativeGuestMachinePath(path) {
		return NativeGuestMachineProvisioningConfiguration{}, nil, NativeGuestMachineProvisioningConfigurationInvalidError{reason: "path is not a safe absolute Host path"}
	}
	data, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) || errors.Is(err, os.ErrPermission) {
			return NativeGuestMachineProvisioningConfiguration{}, nil, NativeGuestMachineProvisioningConfigurationUnavailableError{reason: "file cannot be read"}
		}
		return NativeGuestMachineProvisioningConfiguration{}, nil, NativeGuestMachineProvisioningConfigurationUnavailableError{reason: "file read failed"}
	}
	decoder := json.NewDecoder(strings.NewReader(string(data)))
	decoder.DisallowUnknownFields()
	var configuration NativeGuestMachineProvisioningConfiguration
	if err := decoder.Decode(&configuration); err != nil {
		return NativeGuestMachineProvisioningConfiguration{}, nil, NativeGuestMachineProvisioningConfigurationInvalidError{reason: "JSON cannot be decoded"}
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return NativeGuestMachineProvisioningConfiguration{}, nil, NativeGuestMachineProvisioningConfigurationInvalidError{reason: "must contain exactly one JSON document"}
	}
	if err := configuration.Validate(); err != nil {
		return NativeGuestMachineProvisioningConfiguration{}, nil, NativeGuestMachineProvisioningConfigurationInvalidError{reason: err.Error()}
	}
	return configuration, data, nil
}

// ValidateConfiguredNativeGuestMachineSelection checks only the identity
// relationship between C33 bridge flags and optional C62. It deliberately does
// not execute a provision effect and never substitutes a native machine.
func ValidateConfiguredNativeGuestMachineSelection(kind string, configurationPath string, bridgeConfiguration Config) *Issue {
	if strings.TrimSpace(configurationPath) == "" {
		return nil
	}
	configuration, _, err := LoadNativeGuestMachineProvisioningConfiguration(strings.TrimSpace(configurationPath))
	if err != nil {
		var unavailable NativeGuestMachineProvisioningConfigurationUnavailableError
		if errors.As(err, &unavailable) {
			return &Issue{Code: kind + "-native-guest-machine-configuration-unavailable", Message: "C62 native Guest machine configuration cannot be read", Retryable: boolPointer(true), Dependency: kind}
		}
		return &Issue{Code: kind + "-native-guest-machine-configuration-invalid", Message: "C62 native Guest machine configuration is invalid", Retryable: boolPointer(false), Dependency: kind}
	}
	if configuration.ProviderKind != kind || configuration.ProviderID != bridgeConfiguration.ProviderID || configuration.GuestMachine.MachineID != bridgeConfiguration.VirtualMachine {
		return &Issue{Code: kind + "-native-guest-machine-configuration-mismatch", Message: "C62 provider kind, provider ID, and machine ID must match C33 native bridge inputs", Retryable: boolPointer(false), Dependency: kind}
	}
	return nil
}

func (configuration NativeGuestMachineProvisioningConfiguration) Validate() error {
	if configuration.SchemaVersion != SchemaVersion || !isNativeGuestMachineIdentifier(configuration.ConfigurationID) || !isNativeGuestMachineIdentifier(configuration.ProviderID) || configuration.GuestArchitecture != "amd64" {
		return fmt.Errorf("schemaVersion, identities, and amd64 Guest architecture must be explicit")
	}
	if configuration.ProviderKind != LinuxKVMlibvirtSystemdProviderKind && configuration.ProviderKind != WindowsHyperVSCMProviderKind {
		return fmt.Errorf("providerKind must select Linux KVM/libvirt or Windows Hyper-V")
	}
	if !isNativeGuestMachineIdentifier(configuration.GuestMachine.MachineID) || configuration.GuestMachine.CPUCount < 1 || configuration.GuestMachine.CPUCount > 256 || configuration.GuestMachine.MemoryMiB < 512 || configuration.GuestMachine.MemoryMiB > 1048576 || !nativeGuestMachineMACAddress.MatchString(configuration.GuestMachine.MACAddress) {
		return fmt.Errorf("Guest machine identity, CPU, memory, and unicast MAC address must be explicit and valid")
	}
	if err := validateNativeGuestArtifactManifestSource(configuration.ReleaseArtifacts.NativeGuestArtifactManifest); err != nil {
		return fmt.Errorf("native Guest artifact manifest: %w", err)
	}
	if err := validateNativeGuestArtifact(configuration.ReleaseArtifacts.BootableGuestDisk); err != nil {
		return fmt.Errorf("bootable Guest disk: %w", err)
	}
	if err := validateNativeGuestArtifact(configuration.ReleaseArtifacts.GuestProductBootstrapVolume); err != nil {
		return fmt.Errorf("Guest Product bootstrap volume: %w", err)
	}
	if configuration.ReleaseArtifacts.BootableGuestDisk.ID != "guest-root" || configuration.ReleaseArtifacts.GuestProductBootstrapVolume.ID != "guest-product-bootstrap" || configuration.ReleaseArtifacts.BootableGuestDisk.SourcePath == configuration.ReleaseArtifacts.GuestProductBootstrapVolume.SourcePath {
		return fmt.Errorf("C65 release artifact roles and source paths must be explicit and distinct")
	}
	if !isSafeNativeGuestMachinePath(configuration.RuntimeStorage.RootDiskPath) || !isSafeNativeGuestMachinePath(configuration.RuntimeStorage.BootstrapVolumePath) || configuration.RuntimeStorage.RootDiskPath == configuration.RuntimeStorage.BootstrapVolumePath || configuration.RuntimeStorage.RootDiskPath == configuration.ProvisioningReceiptPath || configuration.RuntimeStorage.BootstrapVolumePath == configuration.ProvisioningReceiptPath || configuration.RuntimeStorage.ExistingRuntimeStoragePolicy != "retain-when-receipt-matches-release-artifacts" || !isSafeNativeGuestMachinePath(configuration.ProvisioningReceiptPath) {
		return fmt.Errorf("runtime storage paths, retained-storage policy, and receipt path must be explicit and distinct")
	}
	for _, path := range []string{configuration.ReleaseArtifacts.NativeGuestArtifactManifest.SourcePath, configuration.ReleaseArtifacts.BootableGuestDisk.SourcePath, configuration.ReleaseArtifacts.GuestProductBootstrapVolume.SourcePath} {
		if path == configuration.RuntimeStorage.RootDiskPath || path == configuration.RuntimeStorage.BootstrapVolumePath || path == configuration.ProvisioningReceiptPath {
			return fmt.Errorf("immutable release artifact paths must be distinct from mutable storage and receipt paths")
		}
	}
	if err := configuration.Native.validateFor(configuration.ProviderKind); err != nil {
		return err
	}
	if configuration.ProviderKind == LinuxKVMlibvirtSystemdProviderKind {
		for _, path := range []string{configuration.RuntimeStorage.RootDiskPath, configuration.RuntimeStorage.BootstrapVolumePath, configuration.ProvisioningReceiptPath, configuration.ReleaseArtifacts.NativeGuestArtifactManifest.SourcePath, configuration.ReleaseArtifacts.BootableGuestDisk.SourcePath, configuration.ReleaseArtifacts.GuestProductBootstrapVolume.SourcePath} {
			if configuration.Native.UEFINvramPath == path {
				return fmt.Errorf("Linux UEFI NVRAM path must be distinct from release artifacts, runtime storage, and C63 receipt")
			}
		}
	}
	return nil
}

func validateNativeGuestArtifact(artifact NativeGuestArtifact) error {
	if !isNativeGuestMachineIdentifier(artifact.ID) || !isSafeNativeGuestMachinePath(artifact.SourcePath) || artifact.SizeBytes < 1 || !nativeGuestMachineSHA256.MatchString(artifact.SHA256) || artifact.StorageImageFormat != "raw" {
		return fmt.Errorf("id, safe source path, positive size, lowercase SHA-256, and raw image format are required")
	}
	return nil
}

func validateNativeGuestArtifactManifestSource(manifest NativeGuestArtifactManifestSource) error {
	if !isSafeNativeGuestMachinePath(manifest.SourcePath) || manifest.SizeBytes < 1 || manifest.SizeBytes > 1048576 || !nativeGuestMachineSHA256.MatchString(manifest.SHA256) {
		return fmt.Errorf("safe source path, size up to 1 MiB, and lowercase SHA-256 are required")
	}
	return nil
}

func (native NativeGuestNativeProvider) validateFor(providerKind string) error {
	if !isSafeNativeGuestMachinePath(native.ImageConverterExecutablePath) {
		return fmt.Errorf("native image converter executable path is required")
	}
	switch providerKind {
	case LinuxKVMlibvirtSystemdProviderKind:
		if native.Kind != "linux-kvm-libvirt" || !isSafeNativeGuestMachinePath(native.LibvirtExecutablePath) || !isSafeNativeGuestMachinePath(native.EmulatorExecutablePath) || !isSafeNativeGuestMachinePath(native.UEFILoaderPath) || !isSafeNativeGuestMachinePath(native.UEFINvramTemplatePath) || !isSafeNativeGuestMachinePath(native.UEFINvramPath) || !isNativeGuestMachineIdentifier(native.LibvirtNetworkName) || native.RuntimeImageFormat != "qcow2" || native.HyperVPowerShellExecutablePath != "" || native.VirtualSwitchName != "" {
			return fmt.Errorf("Linux KVM/libvirt fields must be complete without Windows Hyper-V fields")
		}
	case WindowsHyperVSCMProviderKind:
		if native.Kind != "windows-hyperv" || !isSafeNativeGuestMachinePath(native.HyperVPowerShellExecutablePath) || !isNativeGuestMachineIdentifier(native.VirtualSwitchName) || native.RuntimeImageFormat != "vhdx" || native.LibvirtExecutablePath != "" || native.EmulatorExecutablePath != "" || native.UEFILoaderPath != "" || native.UEFINvramTemplatePath != "" || native.UEFINvramPath != "" || native.LibvirtNetworkName != "" {
			return fmt.Errorf("Windows Hyper-V fields must be complete without Linux KVM/libvirt fields")
		}
	default:
		return fmt.Errorf("native provider kind is unsupported")
	}
	return nil
}

func isNativeGuestMachineIdentifier(value string) bool {
	return nativeGuestMachineIdentifier.MatchString(value)
}

func isSafeNativeGuestMachinePath(value string) bool {
	if strings.TrimSpace(value) != value || strings.ContainsRune(value, '\x00') || value == "" {
		return false
	}
	if !(strings.HasPrefix(value, "/") && !strings.Contains(value, `\\`)) && !nativeGuestMachineWindowsPath.MatchString(value) {
		return false
	}
	for _, component := range strings.FieldsFunc(value, func(character rune) bool { return character == '/' || character == '\\' }) {
		if component == ".." {
			return false
		}
	}
	return true
}

// ProvisionNativeGuestMachine is the selected native provider effect. It
// verifies immutable source bytes before it creates a copy-once runtime disk,
// refuses unreceipted residue, and writes C63 only after all native effects
// succeed. It does not start the Guest and does not report Guest readiness.
func ProvisionNativeGuestMachine(
	ctx context.Context,
	providerKind string,
	configuration NativeGuestMachineProvisioningConfiguration,
	configurationBytes []byte,
	executor Executor,
	clock Clock,
	hostPlatform string,
) (NativeGuestMachineProvisioningResult, error) {
	if executor == nil || clock == nil {
		return NativeGuestMachineProvisioningResult{}, fmt.Errorf("native Guest provisioner requires an executor and clock")
	}
	if err := configuration.Validate(); err != nil {
		return NativeGuestMachineProvisioningResult{}, fmt.Errorf("C62 configuration is invalid: %w", err)
	}
	if providerKind != configuration.ProviderKind {
		return NativeGuestMachineProvisioningResult{}, fmt.Errorf("selected provider kind does not match C62")
	}
	if expectedHostPlatform(providerKind) != contractHostPlatform(hostPlatform) {
		return NativeGuestMachineProvisioningResult{}, fmt.Errorf("selected provider cannot provision on this Host platform")
	}
	if len(configurationBytes) == 0 {
		return NativeGuestMachineProvisioningResult{}, fmt.Errorf("C62 configuration bytes are required for C63 correlation")
	}
	configurationDigest := sha256Hex(configurationBytes)
	manifest, err := verifyNativeGuestArtifactManifest(configuration)
	if err != nil {
		return NativeGuestMachineProvisioningResult{}, err
	}
	if err := verifyNativeGuestArtifactBytes(configuration.ReleaseArtifacts.BootableGuestDisk); err != nil {
		return NativeGuestMachineProvisioningResult{}, err
	}
	if err := verifyNativeGuestArtifactBytes(configuration.ReleaseArtifacts.GuestProductBootstrapVolume); err != nil {
		return NativeGuestMachineProvisioningResult{}, err
	}

	runtimeStatePaths := []string{configuration.RuntimeStorage.RootDiskPath, configuration.RuntimeStorage.BootstrapVolumePath, configuration.ProvisioningReceiptPath}
	if providerKind == LinuxKVMlibvirtSystemdProviderKind {
		runtimeStatePaths = append(runtimeStatePaths, configuration.Native.UEFINvramPath)
	}
	existing, err := existingNativeGuestMachinePaths(runtimeStatePaths)
	if err != nil {
		return NativeGuestMachineProvisioningResult{}, err
	}
	machinePresent, err := observeNativeGuestMachinePresence(ctx, providerKind, configuration, executor)
	if err != nil {
		return NativeGuestMachineProvisioningResult{}, err
	}
	if anyNativeGuestMachinePathExists(existing) || machinePresent {
		receipt, err := loadNativeGuestMachineProvisioningReceipt(configuration.ProvisioningReceiptPath)
		if err != nil {
			return NativeGuestMachineProvisioningResult{}, fmt.Errorf("existing native Guest resources require a readable matching C63 receipt: %w", err)
		}
		if !matchesNativeGuestMachineReceipt(configuration, configurationDigest, manifest, receipt) {
			return NativeGuestMachineProvisioningResult{}, fmt.Errorf("existing native Guest resources do not match C62 immutable release inputs")
		}
		if !allNativeGuestMachinePathsExist(existing) || !machinePresent {
			return NativeGuestMachineProvisioningResult{}, fmt.Errorf("C63 receipt matches but native Guest resources are incomplete")
		}
		return NativeGuestMachineProvisioningResult{Receipt: receipt, Retained: true}, nil
	}

	if err := convertNativeGuestRuntimeStorage(ctx, providerKind, configuration, executor); err != nil {
		return NativeGuestMachineProvisioningResult{}, err
	}
	if err := verifyNativeGuestRuntimeStorageCreated(configuration); err != nil {
		return NativeGuestMachineProvisioningResult{}, err
	}
	if err := defineNativeGuestMachine(ctx, providerKind, configuration, executor); err != nil {
		return NativeGuestMachineProvisioningResult{}, err
	}
	receipt := nativeGuestMachineReceipt(configuration, configurationDigest, manifest, timestamp(clock))
	if err := writeNativeGuestMachineProvisioningReceipt(configuration.ProvisioningReceiptPath, receipt); err != nil {
		return NativeGuestMachineProvisioningResult{}, err
	}
	return NativeGuestMachineProvisioningResult{Receipt: receipt}, nil
}

func expectedHostPlatform(providerKind string) string {
	if providerKind == LinuxKVMlibvirtSystemdProviderKind {
		return "linux"
	}
	if providerKind == WindowsHyperVSCMProviderKind {
		return "windows"
	}
	return "unknown"
}

func verifyNativeGuestArtifactBytes(artifact NativeGuestArtifact) error {
	return verifyNativeGuestFile(artifact.SourcePath, artifact.SizeBytes, artifact.SHA256, "C62 release artifact "+artifact.ID)
}

func verifyNativeGuestFile(path string, sizeBytes int64, expectedSHA256 string, label string) error {
	info, err := os.Lstat(path)
	if err != nil {
		return fmt.Errorf("%s is unavailable: %w", label, err)
	}
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || info.Size() != sizeBytes {
		return fmt.Errorf("%s differs from its declared regular-file size", label)
	}
	file, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("%s cannot be read: %w", label, err)
	}
	hash := sha256.New()
	_, copyErr := io.Copy(hash, file)
	closeErr := file.Close()
	if copyErr != nil || closeErr != nil {
		return fmt.Errorf("%s cannot be hashed", label)
	}
	if hex.EncodeToString(hash.Sum(nil)) != expectedSHA256 {
		return fmt.Errorf("%s SHA-256 differs from its declaration", label)
	}
	return nil
}

func readVerifiedNativeGuestManifest(source NativeGuestArtifactManifestSource) ([]byte, error) {
	if err := verifyNativeGuestFile(source.SourcePath, source.SizeBytes, source.SHA256, "C65 native Guest artifact manifest"); err != nil {
		return nil, err
	}
	data, err := os.ReadFile(source.SourcePath)
	if err != nil {
		return nil, fmt.Errorf("C65 native Guest artifact manifest cannot be read: %w", err)
	}
	return data, nil
}

// verifyNativeGuestArtifactManifest enforces the compiler-to-provisioner
// boundary. A provider may copy only the two files described by the exact C65
// document whose own Host file identity C62 names. It never creates a missing
// manifest, infers an image role, or accepts an equivalent-looking file.
func verifyNativeGuestArtifactManifest(configuration NativeGuestMachineProvisioningConfiguration) (NativeGuestArtifactManifest, error) {
	source := configuration.ReleaseArtifacts.NativeGuestArtifactManifest
	data, err := readVerifiedNativeGuestManifest(source)
	if err != nil {
		return NativeGuestArtifactManifest{}, err
	}
	decoder := json.NewDecoder(strings.NewReader(string(data)))
	decoder.DisallowUnknownFields()
	var manifest NativeGuestArtifactManifest
	if err := decoder.Decode(&manifest); err != nil {
		return NativeGuestArtifactManifest{}, fmt.Errorf("C65 native Guest artifact manifest cannot be decoded: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return NativeGuestArtifactManifest{}, fmt.Errorf("C65 native Guest artifact manifest must contain exactly one JSON document")
	}
	if err := validateNativeGuestArtifactManifest(manifest); err != nil {
		return NativeGuestArtifactManifest{}, fmt.Errorf("C65 native Guest artifact manifest is invalid: %w", err)
	}
	if err := manifestMatchesNativeGuestReleaseArtifacts(manifest, configuration.ReleaseArtifacts); err != nil {
		return NativeGuestArtifactManifest{}, err
	}
	return manifest, nil
}

func validateNativeGuestArtifactManifest(manifest NativeGuestArtifactManifest) error {
	if manifest.SchemaVersion != SchemaVersion || !isNativeGuestMachineIdentifier(manifest.ArtifactSetID) || manifest.Architecture != "amd64" || len(manifest.StorageDevices) != 2 {
		return fmt.Errorf("schemaVersion, artifact set identity, amd64 architecture, and exactly two storage devices are required")
	}
	roles := make(map[string]NativeGuestArtifactManifestDevice, len(manifest.StorageDevices))
	for _, device := range manifest.StorageDevices {
		if _, exists := roles[device.Role]; exists || !isNativeGuestMachineIdentifier(device.ID) || device.StorageImageFormat != "raw" || device.SizeBytes < 1 || !nativeGuestMachineSHA256.MatchString(device.SHA256) {
			return fmt.Errorf("each C65 storage device must have one valid raw identity")
		}
		roles[device.Role] = device
	}
	root, rootExists := roles["guest-root-storage"]
	bootstrap, bootstrapExists := roles["guest-product-bootstrap-volume"]
	if !rootExists || !bootstrapExists || root.ID != "guest-root" || root.GuestVolumeFileSystem != nil || bootstrap.ID != "guest-product-bootstrap" || bootstrap.GuestVolumeFileSystem == nil || *bootstrap.GuestVolumeFileSystem != "iso9660" {
		return fmt.Errorf("C65 must declare guest-root raw storage and the ISO9660 Guest Product bootstrap volume by their fixed roles")
	}
	return nil
}

func manifestMatchesNativeGuestReleaseArtifacts(manifest NativeGuestArtifactManifest, releaseArtifacts NativeGuestReleaseArtifacts) error {
	devices := make(map[string]NativeGuestArtifactManifestDevice, len(manifest.StorageDevices))
	for _, device := range manifest.StorageDevices {
		devices[device.Role] = device
	}
	for _, expected := range []struct {
		role     string
		artifact NativeGuestArtifact
	}{
		{role: "guest-root-storage", artifact: releaseArtifacts.BootableGuestDisk},
		{role: "guest-product-bootstrap-volume", artifact: releaseArtifacts.GuestProductBootstrapVolume},
	} {
		device := devices[expected.role]
		if device.ID != expected.artifact.ID || device.StorageImageFormat != expected.artifact.StorageImageFormat || device.SizeBytes != expected.artifact.SizeBytes || device.SHA256 != expected.artifact.SHA256 {
			return fmt.Errorf("C65 native Guest artifact manifest does not match C62 release artifact %s", expected.artifact.ID)
		}
	}
	return nil
}

func existingNativeGuestMachinePaths(paths []string) (map[string]bool, error) {
	existing := make(map[string]bool, len(paths))
	for _, path := range paths {
		info, err := os.Lstat(path)
		if errors.Is(err, os.ErrNotExist) {
			existing[path] = false
			continue
		}
		if err != nil {
			return nil, fmt.Errorf("native Guest state path %s cannot be observed: %w", path, err)
		}
		if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
			return nil, fmt.Errorf("native Guest state path %s must be a regular non-symlink file", path)
		}
		existing[path] = true
	}
	return existing, nil
}

func anyNativeGuestMachinePathExists(paths map[string]bool) bool {
	for _, exists := range paths {
		if exists {
			return true
		}
	}
	return false
}

func allNativeGuestMachinePathsExist(paths map[string]bool) bool {
	for _, exists := range paths {
		if !exists {
			return false
		}
	}
	return true
}

func observeNativeGuestMachinePresence(ctx context.Context, providerKind string, configuration NativeGuestMachineProvisioningConfiguration, executor Executor) (bool, error) {
	var command Command
	switch providerKind {
	case LinuxKVMlibvirtSystemdProviderKind:
		command = Command{Name: configuration.Native.LibvirtExecutablePath, Args: []string{"list", "--all", "--name"}}
	case WindowsHyperVSCMProviderKind:
		command = Command{Name: configuration.Native.HyperVPowerShellExecutablePath, Args: []string{"-NoProfile", "-NonInteractive", "-Command", "if ($null -eq (Get-VM -Name " + powershellQuoted(configuration.GuestMachine.MachineID) + " -ErrorAction SilentlyContinue)) { [Console]::Out.Write('absent') } else { [Console]::Out.Write('present') }"}}
	default:
		return false, fmt.Errorf("selected native provider is unsupported")
	}
	output, err := executor.Run(ctx, command)
	if err != nil {
		return false, fmt.Errorf("observe native Guest machine presence: %w", err)
	}
	switch providerKind {
	case LinuxKVMlibvirtSystemdProviderKind:
		for _, name := range strings.Fields(output) {
			if name == configuration.GuestMachine.MachineID {
				return true, nil
			}
		}
		return false, nil
	case WindowsHyperVSCMProviderKind:
		switch strings.TrimSpace(strings.ToLower(output)) {
		case "present":
			return true, nil
		case "absent":
			return false, nil
		default:
			return false, fmt.Errorf("Hyper-V machine-presence observation returned an unrecognized state")
		}
	}
	return false, fmt.Errorf("selected native provider is unsupported")
}

func convertNativeGuestRuntimeStorage(ctx context.Context, providerKind string, configuration NativeGuestMachineProvisioningConfiguration, executor Executor) error {
	format := configuration.Native.RuntimeImageFormat
	for _, conversion := range []struct {
		source NativeGuestArtifact
		target string
	}{
		{source: configuration.ReleaseArtifacts.BootableGuestDisk, target: configuration.RuntimeStorage.RootDiskPath},
		{source: configuration.ReleaseArtifacts.GuestProductBootstrapVolume, target: configuration.RuntimeStorage.BootstrapVolumePath},
	} {
		command := Command{Name: configuration.Native.ImageConverterExecutablePath, Args: []string{"convert", "-f", "raw", "-O", format, conversion.source.SourcePath, conversion.target}}
		if _, err := executor.Run(ctx, command); err != nil {
			return fmt.Errorf("convert declared %s into native runtime storage: %w", conversion.source.ID, err)
		}
	}
	return nil
}

func verifyNativeGuestRuntimeStorageCreated(configuration NativeGuestMachineProvisioningConfiguration) error {
	for _, path := range []string{configuration.RuntimeStorage.RootDiskPath, configuration.RuntimeStorage.BootstrapVolumePath} {
		info, err := os.Lstat(path)
		if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || info.Size() < 1 {
			return fmt.Errorf("native image conversion did not publish declared runtime storage %s", path)
		}
	}
	return nil
}

func defineNativeGuestMachine(ctx context.Context, providerKind string, configuration NativeGuestMachineProvisioningConfiguration, executor Executor) error {
	switch providerKind {
	case LinuxKVMlibvirtSystemdProviderKind:
		return defineLinuxKVMlibvirtGuestMachine(ctx, configuration, executor)
	case WindowsHyperVSCMProviderKind:
		return defineWindowsHyperVGuestMachine(ctx, configuration, executor)
	default:
		return fmt.Errorf("selected native provider is unsupported")
	}
}

func defineLinuxKVMlibvirtGuestMachine(ctx context.Context, configuration NativeGuestMachineProvisioningConfiguration, executor Executor) error {
	definition, err := renderLinuxKVMlibvirtDomainDefinition(configuration)
	if err != nil {
		return err
	}
	definitionFile, err := os.CreateTemp(filepath.Dir(configuration.ProvisioningReceiptPath), ".native-guest-domain-*.xml")
	if err != nil {
		return fmt.Errorf("create transient libvirt domain definition: %w", err)
	}
	definitionPath := definitionFile.Name()
	defer os.Remove(definitionPath)
	if _, err := definitionFile.Write(definition); err != nil {
		definitionFile.Close()
		return fmt.Errorf("write transient libvirt domain definition: %w", err)
	}
	if err := definitionFile.Close(); err != nil {
		return fmt.Errorf("close transient libvirt domain definition: %w", err)
	}
	if _, err := executor.Run(ctx, Command{Name: configuration.Native.LibvirtExecutablePath, Args: []string{"define", definitionPath}}); err != nil {
		return fmt.Errorf("define declared libvirt Guest machine: %w", err)
	}
	if _, err := executor.Run(ctx, Command{Name: configuration.Native.LibvirtExecutablePath, Args: []string{"autostart", configuration.GuestMachine.MachineID}}); err != nil {
		return fmt.Errorf("enable declared libvirt Guest machine autostart: %w", err)
	}
	return nil
}

func renderLinuxKVMlibvirtDomainDefinition(configuration NativeGuestMachineProvisioningConfiguration) ([]byte, error) {
	escape := func(value string) (string, error) {
		var buffer strings.Builder
		if err := xml.EscapeText(&buffer, []byte(value)); err != nil {
			return "", err
		}
		return buffer.String(), nil
	}
	values := []string{
		configuration.GuestMachine.MachineID, configuration.Native.EmulatorExecutablePath, configuration.Native.UEFILoaderPath,
		configuration.Native.UEFINvramTemplatePath, configuration.Native.UEFINvramPath, configuration.RuntimeStorage.RootDiskPath,
		configuration.RuntimeStorage.BootstrapVolumePath, configuration.Native.LibvirtNetworkName, strings.ToLower(configuration.GuestMachine.MACAddress),
	}
	escaped := make([]string, len(values))
	for index, value := range values {
		var err error
		escaped[index], err = escape(value)
		if err != nil {
			return nil, fmt.Errorf("escape libvirt domain configuration: %w", err)
		}
	}
	definition := fmt.Sprintf("<domain type='kvm'><name>%s</name><memory unit='MiB'>%d</memory><currentMemory unit='MiB'>%d</currentMemory><vcpu placement='static'>%d</vcpu><os><type arch='x86_64' machine='q35'>hvm</type><loader readonly='yes' type='pflash'>%s</loader><nvram template='%s'>%s</nvram></os><features><acpi/></features><devices><emulator>%s</emulator><disk type='file' device='disk'><driver name='qemu' type='qcow2'/><source file='%s'/><target dev='vda' bus='virtio'/></disk><disk type='file' device='disk'><driver name='qemu' type='qcow2'/><source file='%s'/><target dev='vdb' bus='virtio'/><readonly/></disk><interface type='network'><mac address='%s'/><source network='%s'/><model type='virtio'/></interface><console type='pty'/><graphics type='none'/></devices></domain>", escaped[0], configuration.GuestMachine.MemoryMiB, configuration.GuestMachine.MemoryMiB, configuration.GuestMachine.CPUCount, escaped[2], escaped[3], escaped[4], escaped[1], escaped[5], escaped[6], escaped[8], escaped[7])
	return []byte(definition), nil
}

func defineWindowsHyperVGuestMachine(ctx context.Context, configuration NativeGuestMachineProvisioningConfiguration, executor Executor) error {
	machineID := powershellQuoted(configuration.GuestMachine.MachineID)
	rootDiskPath := powershellQuoted(configuration.RuntimeStorage.RootDiskPath)
	bootstrapPath := powershellQuoted(configuration.RuntimeStorage.BootstrapVolumePath)
	switchName := powershellQuoted(configuration.Native.VirtualSwitchName)
	macAddress := powershellQuoted(strings.ReplaceAll(configuration.GuestMachine.MACAddress, ":", ""))
	script := "$vm = New-VM -Name " + machineID + " -Generation 2 -MemoryStartupBytes " + fmt.Sprintf("%dMB", configuration.GuestMachine.MemoryMiB) + " -VHDPath " + rootDiskPath + " -SwitchName " + switchName + " -ErrorAction Stop; Set-VMProcessor -VMName " + machineID + " -Count " + fmt.Sprintf("%d", configuration.GuestMachine.CPUCount) + " -ErrorAction Stop; Set-VMFirmware -VMName " + machineID + " -EnableSecureBoot Off -ErrorAction Stop; Add-VMHardDiskDrive -VMName " + machineID + " -Path " + bootstrapPath + " -ErrorAction Stop; Set-VMNetworkAdapter -VMName " + machineID + " -StaticMacAddress " + macAddress + " -ErrorAction Stop; Set-VM -VMName " + machineID + " -AutomaticStartAction Nothing -AutomaticStopAction ShutDown -ErrorAction Stop"
	if _, err := executor.Run(ctx, Command{Name: configuration.Native.HyperVPowerShellExecutablePath, Args: []string{"-NoProfile", "-NonInteractive", "-Command", script}}); err != nil {
		return fmt.Errorf("define declared Hyper-V Guest machine: %w", err)
	}
	return nil
}

func nativeGuestMachineReceipt(configuration NativeGuestMachineProvisioningConfiguration, configurationDigest string, manifest NativeGuestArtifactManifest, completedAt string) NativeGuestMachineProvisioningReceipt {
	identity := func(artifact NativeGuestArtifact) NativeGuestArtifactIdentity {
		return NativeGuestArtifactIdentity{ID: artifact.ID, SizeBytes: artifact.SizeBytes, SHA256: artifact.SHA256, StorageImageFormat: artifact.StorageImageFormat}
	}
	return NativeGuestMachineProvisioningReceipt{
		SchemaVersion: SchemaVersion, ConfigurationID: configuration.ConfigurationID, ConfigurationSHA256: configurationDigest,
		ProviderKind: configuration.ProviderKind, ProviderID: configuration.ProviderID, MachineID: configuration.GuestMachine.MachineID, GuestArchitecture: configuration.GuestArchitecture,
		ReleaseArtifacts: NativeGuestReceiptReleaseArtifacts{
			NativeGuestArtifactManifest: NativeGuestArtifactManifestIdentity{ArtifactSetID: manifest.ArtifactSetID, SizeBytes: configuration.ReleaseArtifacts.NativeGuestArtifactManifest.SizeBytes, SHA256: configuration.ReleaseArtifacts.NativeGuestArtifactManifest.SHA256},
			BootableGuestDisk:           identity(configuration.ReleaseArtifacts.BootableGuestDisk),
			GuestProductBootstrapVolume: identity(configuration.ReleaseArtifacts.GuestProductBootstrapVolume),
		},
		RuntimeStorage: NativeGuestReceiptRuntimeStorage{RootDiskPath: configuration.RuntimeStorage.RootDiskPath, BootstrapVolumePath: configuration.RuntimeStorage.BootstrapVolumePath, RuntimeImageFormat: configuration.Native.RuntimeImageFormat},
		CompletedAt:    completedAt,
	}
}

func loadNativeGuestMachineProvisioningReceipt(path string) (NativeGuestMachineProvisioningReceipt, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return NativeGuestMachineProvisioningReceipt{}, err
	}
	decoder := json.NewDecoder(strings.NewReader(string(data)))
	decoder.DisallowUnknownFields()
	var receipt NativeGuestMachineProvisioningReceipt
	if err := decoder.Decode(&receipt); err != nil {
		return NativeGuestMachineProvisioningReceipt{}, err
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return NativeGuestMachineProvisioningReceipt{}, fmt.Errorf("C63 must contain exactly one JSON document")
	}
	if !isNativeGuestMachineReceiptWellFormed(receipt) {
		return NativeGuestMachineProvisioningReceipt{}, fmt.Errorf("C63 is invalid")
	}
	return receipt, nil
}

func isNativeGuestMachineReceiptWellFormed(receipt NativeGuestMachineProvisioningReceipt) bool {
	return receipt.SchemaVersion == SchemaVersion && isNativeGuestMachineIdentifier(receipt.ConfigurationID) && nativeGuestMachineSHA256.MatchString(receipt.ConfigurationSHA256) && (receipt.ProviderKind == LinuxKVMlibvirtSystemdProviderKind || receipt.ProviderKind == WindowsHyperVSCMProviderKind) && isNativeGuestMachineIdentifier(receipt.ProviderID) && isNativeGuestMachineIdentifier(receipt.MachineID) && receipt.GuestArchitecture == "amd64" && isNativeGuestMachineIdentifier(receipt.ReleaseArtifacts.NativeGuestArtifactManifest.ArtifactSetID) && receipt.ReleaseArtifacts.NativeGuestArtifactManifest.SizeBytes > 0 && receipt.ReleaseArtifacts.NativeGuestArtifactManifest.SizeBytes <= 1048576 && nativeGuestMachineSHA256.MatchString(receipt.ReleaseArtifacts.NativeGuestArtifactManifest.SHA256) && receipt.ReleaseArtifacts.BootableGuestDisk.ID == "guest-root" && receipt.ReleaseArtifacts.BootableGuestDisk.SizeBytes > 0 && nativeGuestMachineSHA256.MatchString(receipt.ReleaseArtifacts.BootableGuestDisk.SHA256) && receipt.ReleaseArtifacts.BootableGuestDisk.StorageImageFormat == "raw" && receipt.ReleaseArtifacts.GuestProductBootstrapVolume.ID == "guest-product-bootstrap" && receipt.ReleaseArtifacts.GuestProductBootstrapVolume.SizeBytes > 0 && nativeGuestMachineSHA256.MatchString(receipt.ReleaseArtifacts.GuestProductBootstrapVolume.SHA256) && receipt.ReleaseArtifacts.GuestProductBootstrapVolume.StorageImageFormat == "raw" && isSafeNativeGuestMachinePath(receipt.RuntimeStorage.RootDiskPath) && isSafeNativeGuestMachinePath(receipt.RuntimeStorage.BootstrapVolumePath) && (receipt.RuntimeStorage.RuntimeImageFormat == "qcow2" || receipt.RuntimeStorage.RuntimeImageFormat == "vhdx") && receipt.CompletedAt != ""
}

func matchesNativeGuestMachineReceipt(configuration NativeGuestMachineProvisioningConfiguration, configurationDigest string, manifest NativeGuestArtifactManifest, receipt NativeGuestMachineProvisioningReceipt) bool {
	expected := nativeGuestMachineReceipt(configuration, configurationDigest, manifest, receipt.CompletedAt)
	return receipt.SchemaVersion == expected.SchemaVersion && receipt.ConfigurationID == expected.ConfigurationID && receipt.ConfigurationSHA256 == expected.ConfigurationSHA256 && receipt.ProviderKind == expected.ProviderKind && receipt.ProviderID == expected.ProviderID && receipt.MachineID == expected.MachineID && receipt.GuestArchitecture == expected.GuestArchitecture && receipt.ReleaseArtifacts == expected.ReleaseArtifacts && receipt.RuntimeStorage == expected.RuntimeStorage
}

func writeNativeGuestMachineProvisioningReceipt(path string, receipt NativeGuestMachineProvisioningReceipt) error {
	encoded, err := json.MarshalIndent(receipt, "", "  ")
	if err != nil {
		return fmt.Errorf("encode C63 receipt: %w", err)
	}
	encoded = append(encoded, '\n')
	temporary, err := os.CreateTemp(filepath.Dir(path), ".native-guest-provisioning-receipt-*")
	if err != nil {
		return fmt.Errorf("create C63 receipt staging file: %w", err)
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if _, err := temporary.Write(encoded); err != nil {
		temporary.Close()
		return fmt.Errorf("write C63 receipt staging file: %w", err)
	}
	if err := temporary.Chmod(0o600); err != nil {
		temporary.Close()
		return fmt.Errorf("set C63 receipt permissions: %w", err)
	}
	if err := temporary.Close(); err != nil {
		return fmt.Errorf("close C63 receipt staging file: %w", err)
	}
	if err := os.Rename(temporaryPath, path); err != nil {
		return fmt.Errorf("publish C63 receipt: %w", err)
	}
	return nil
}

func sha256Hex(value []byte) string {
	sum := sha256.Sum256(value)
	return hex.EncodeToString(sum[:])
}
