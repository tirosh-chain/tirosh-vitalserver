// Package productupdatecomposition owns release-process-only preparation of a
// complete Product Update Specification and its immutable payload. It does not
// sign the bootstrap envelope or activate runtime state.
package productupdatecomposition

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

const (
	schemaVersion                    = "v1"
	guestReleaseArchiveMedia         = "application/vnd.tirosh.vitalserver.guest-product-release+tar+gzip"
	effectExecutorMedia              = "application/vnd.tirosh.vitalserver.update-layer-effect-executor"
	effectConfigurationMedia         = "application/vnd.tirosh.vitalserver.update-layer-effect-configuration+json"
	imageSetArchiveMedia             = "application/vnd.tirosh.vitalserver.bundled-upstream-image-set+tar+gzip"
	hostPlatformReleaseArchiveMedia  = "application/vnd.tirosh.vitalserver.host-platform-release+tar+gzip"
	maximumCompositionBytes          = 1 << 20
	guestProductReleaseRoot          = "/opt/vitalserver/releases/"
	guestReleaseManagerPath          = "/v1/guest-product-release-updates"
	macOSHostInstallationManagerPath = "/Library/Application Support/VitalServerRuntimePlatform/current/bin/host-installation-manager"
	macOSActiveReleaseManifestPath   = "/Library/Application Support/VitalServerRuntimePlatform/current/installation-manifest.json"
)

var identifierPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$`)

// ProductUpdateComposition is a build-local complete Product release
// selection. Source paths are consumed only by this release tool and never
// leave the trusted release workspace. Deployed bootstrap, specification, and
// layer configuration documents carry immutable identities instead.
type ProductUpdateComposition struct {
	SchemaVersion   string                   `json:"schemaVersion"`
	BundleID        string                   `json:"bundleId"`
	ProductID       string                   `json:"productId"`
	Target          UpdateTarget             `json:"target"`
	TargetRelease   TargetRelease            `json:"targetRelease"`
	SigningKeyID    string                   `json:"signingKeyId"`
	IssuedAt        string                   `json:"issuedAt"`
	SpecificationID string                   `json:"specificationId"`
	NextUpdater     SourceArtifact           `json:"nextUpdater"`
	GuestRuntime    GuestRuntimeUpdateSource `json:"guestRuntime"`
	// BundledUpstreamImageSet is optional because an external-Upstream release
	// has no Guest-owned Container layer. When present it is always emitted
	// before the Guest Runtime layer in the bootstrap and detailed plan.
	BundledUpstreamImageSet *GuestBundledUpstreamImageSetUpdateSource `json:"bundledUpstreamImageSet,omitempty"`
	// HostPlatformRelease is optional for a Guest-only update. When present it
	// is always emitted after every Guest-owned layer because it may replace
	// the Host updater and service boundary executing this handoff.
	HostPlatformRelease *HostPlatformReleaseUpdateSource `json:"hostPlatformRelease,omitempty"`
}

type UpdateTarget struct {
	Platform     string `json:"platform"`
	Architecture string `json:"architecture"`
}

type TargetRelease struct {
	ProductVersion string `json:"productVersion"`
	RuntimeVersion string `json:"runtimeVersion"`
}

type SourceArtifact struct {
	ID         string `json:"id"`
	SourcePath string `json:"sourcePath"`
}

// GuestRuntimeUpdateSource keeps the Guest Runtime layer's selected Product
// release and its release-owned effect executor under one explicit owner.
type GuestRuntimeUpdateSource struct {
	ProductRelease GuestProductReleaseUpdateSource         `json:"productRelease"`
	EffectExecutor GuestProductReleaseEffectExecutorSource `json:"effectExecutor"`
}

type GuestProductReleaseUpdateSource struct {
	Apply    GuestProductReleaseTransitionSource  `json:"apply"`
	Rollback *GuestProductReleaseTransitionSource `json:"rollback,omitempty"`
}

type GuestProductReleaseTransitionSource struct {
	ExpectedActiveReleaseID string         `json:"expectedActiveReleaseId"`
	TargetReleaseID         string         `json:"targetReleaseId"`
	TargetReleaseDirectory  string         `json:"targetReleaseDirectory"`
	Artifact                SourceArtifact `json:"artifact"`
}

type GuestProductReleaseEffectExecutorSource struct {
	Executor                       SourceArtifact `json:"executor"`
	ConfigurationArtifactID        string         `json:"configurationArtifactId"`
	GuestProductReleaseManagerPort int            `json:"guestProductReleaseManagerPort"`
	RequestTimeoutMilliseconds     int            `json:"requestTimeoutMilliseconds"`
}

// GuestBundledUpstreamImageSetUpdateSource is the release-process input for
// Container layer. It names immutable archive and effect-executor bytes, while
// the active image-set remains the Guest image-set manager's state.
type GuestBundledUpstreamImageSetUpdateSource struct {
	Apply          GuestBundledUpstreamImageSetTransitionSource     `json:"apply"`
	Rollback       *GuestBundledUpstreamImageSetTransitionSource    `json:"rollback,omitempty"`
	EffectExecutor GuestBundledUpstreamImageSetEffectExecutorSource `json:"effectExecutor"`
}

type GuestBundledUpstreamImageSetTransitionSource struct {
	ExpectedActiveImageSet activeImageSetSelection `json:"expectedActiveImageSet"`
	TargetImageSetID       string                  `json:"targetImageSetId"`
	Artifact               SourceArtifact          `json:"artifact"`
}

type GuestBundledUpstreamImageSetEffectExecutorSource struct {
	Executor                   SourceArtifact `json:"executor"`
	ConfigurationArtifactID    string         `json:"configurationArtifactId"`
	ImageSetManagerPort        int            `json:"imageSetManagerPort"`
	RequestTimeoutMilliseconds int            `json:"requestTimeoutMilliseconds"`
}

// HostPlatformReleaseUpdateSource is the release-process selection for the
// final Host Platform layer. The fixed installed Installation Manager paths
// are derived from Target.Platform rather than accepted from release input.
type HostPlatformReleaseUpdateSource struct {
	Apply          HostPlatformReleaseTransitionSource     `json:"apply"`
	Rollback       *HostPlatformReleaseTransitionSource    `json:"rollback,omitempty"`
	EffectExecutor HostPlatformReleaseEffectExecutorSource `json:"effectExecutor"`
}

type HostPlatformReleaseTransitionSource struct {
	ExpectedActiveReleaseID string         `json:"expectedActiveReleaseId"`
	TargetReleaseID         string         `json:"targetReleaseId"`
	Artifact                SourceArtifact `json:"artifact"`
}

type HostPlatformReleaseEffectExecutorSource struct {
	Executor                   SourceArtifact `json:"executor"`
	ConfigurationArtifactID    string         `json:"configurationArtifactId"`
	RequestTimeoutMilliseconds int            `json:"requestTimeoutMilliseconds"`
}

type ComposeProductUpdateRequest struct {
	CompositionPath string
	OutputDirectory string
}

// ComposedProductUpdate contains the prepared inputs to the
// generic signer. The generic signer remains the sole bootstrap-envelope
// signing owner.
type ComposedProductUpdate struct {
	OutputDirectory                     string `json:"outputDirectory"`
	PayloadDirectory                    string `json:"payloadDirectory"`
	ReleaseBundleCompositionPath        string `json:"releaseBundleCompositionPath"`
	ProductUpdateSpecificationPath      string `json:"productUpdateSpecificationPath"`
	EffectConfigurationPath             string `json:"effectConfigurationPath"`
	ContainerEffectConfigurationPath    string `json:"containerEffectConfigurationPath,omitempty"`
	HostPlatformEffectConfigurationPath string `json:"hostPlatformEffectConfigurationPath,omitempty"`
}

type releaseBundleComposition struct {
	SchemaVersion string                     `json:"schemaVersion"`
	BundleID      string                     `json:"bundleId"`
	ProductID     string                     `json:"productId"`
	Target        UpdateTarget               `json:"target"`
	TargetRelease TargetRelease              `json:"targetRelease"`
	LayerOrder    []string                   `json:"layerOrder"`
	NextUpdater   releaseArtifactDeclaration `json:"nextUpdater"`
	Specification releaseArtifactDeclaration `json:"specification"`
	SigningKeyID  string                     `json:"signingKeyId"`
	IssuedAt      string                     `json:"issuedAt"`
}

type releaseArtifactDeclaration struct {
	ID           string `json:"id"`
	RelativePath string `json:"relativePath"`
	MediaType    string `json:"mediaType"`
}

type productUpdateSpecification struct {
	SchemaVersion       string                   `json:"schemaVersion"`
	ID                  string                   `json:"id"`
	BootstrapEnvelopeID string                   `json:"bootstrapEnvelopeId"`
	LayerPlan           []productUpdateLayerPlan `json:"layerPlan"`
}

type productUpdateLayerPlan struct {
	Layer          string                      `json:"layer"`
	DependsOn      []string                    `json:"dependsOn"`
	Artifact       payloadArtifact             `json:"artifact"`
	EffectExecutor productUpdateEffectExecutor `json:"effectExecutor"`
	Rollback       productUpdateRollback       `json:"rollback"`
}

type payloadArtifact struct {
	ID           string `json:"id"`
	RelativePath string `json:"relativePath"`
	SHA256       string `json:"sha256"`
	SizeBytes    int64  `json:"sizeBytes"`
	MediaType    string `json:"mediaType"`
}

type productUpdateEffectExecutor struct {
	ID                    string          `json:"id"`
	RelativePath          string          `json:"relativePath"`
	SHA256                string          `json:"sha256"`
	SizeBytes             int64           `json:"sizeBytes"`
	MediaType             string          `json:"mediaType"`
	ConfigurationArtifact payloadArtifact `json:"configurationArtifact"`
}

type productUpdateRollback struct {
	State    string           `json:"state"`
	Artifact *payloadArtifact `json:"artifact,omitempty"`
	Reason   string           `json:"reason,omitempty"`
}

type guestProductReleaseEffectExecutorConfiguration struct {
	SchemaVersion                      string                              `json:"schemaVersion"`
	EffectExecutorID                   string                              `json:"effectExecutorId"`
	GuestProductReleaseManagerEndpoint guestProductReleaseManagerEndpoint  `json:"guestProductReleaseManagerEndpoint"`
	Apply                              guestProductReleaseOperationIntent  `json:"apply"`
	Rollback                           *guestProductReleaseOperationIntent `json:"rollback,omitempty"`
}

type guestProductReleaseManagerEndpoint struct {
	Scheme                     string `json:"scheme"`
	Host                       string `json:"host"`
	Port                       int    `json:"port"`
	Path                       string `json:"path"`
	RequestTimeoutMilliseconds int    `json:"requestTimeoutMilliseconds"`
}

type guestProductReleaseOperationIntent struct {
	ExpectedActiveReleaseID string `json:"expectedActiveReleaseId"`
	TargetReleaseID         string `json:"targetReleaseId"`
	TargetReleaseDirectory  string `json:"targetReleaseDirectory"`
}

type activeImageSetSelection struct {
	State      string `json:"state"`
	ImageSetID string `json:"imageSetId,omitempty"`
}

type bundledUpstreamImageSetEffectExecutorConfiguration struct {
	SchemaVersion           string                                  `json:"schemaVersion"`
	EffectExecutorID        string                                  `json:"effectExecutorId"`
	ImageSetManagerEndpoint bundledUpstreamImageSetManagerEndpoint  `json:"imageSetManagerEndpoint"`
	Apply                   bundledUpstreamImageSetOperationIntent  `json:"apply"`
	Rollback                *bundledUpstreamImageSetOperationIntent `json:"rollback,omitempty"`
}

type bundledUpstreamImageSetManagerEndpoint struct {
	Scheme                     string `json:"scheme"`
	Host                       string `json:"host"`
	Port                       int    `json:"port"`
	Path                       string `json:"path"`
	RequestTimeoutMilliseconds int    `json:"requestTimeoutMilliseconds"`
}

type bundledUpstreamImageSetOperationIntent struct {
	ExpectedActiveImageSet activeImageSetSelection `json:"expectedActiveImageSet"`
	TargetImageSetID       string                  `json:"targetImageSetId"`
}

type hostPlatformReleaseEffectExecutorConfiguration struct {
	SchemaVersion           string                              `json:"schemaVersion"`
	EffectExecutorID        string                              `json:"effectExecutorId"`
	HostInstallationManager hostInstallationManagerEndpoint     `json:"hostInstallationManager"`
	Apply                   hostPlatformReleaseOperationIntent  `json:"apply"`
	Rollback                *hostPlatformReleaseOperationIntent `json:"rollback,omitempty"`
}

type hostInstallationManagerEndpoint struct {
	Platform                   string `json:"platform"`
	ExecutablePath             string `json:"executablePath"`
	ActiveReleaseManifestPath  string `json:"activeReleaseManifestPath"`
	RequestTimeoutMilliseconds int    `json:"requestTimeoutMilliseconds"`
}

type hostPlatformReleaseOperationIntent struct {
	ExpectedActiveReleaseID string `json:"expectedActiveReleaseId"`
	TargetReleaseID         string `json:"targetReleaseId"`
}

// ComposeProductUpdate copies selected immutable source bytes, derives the
// detailed update plan and layer configuration identities from copied bytes,
// and emits a bootstrap signer input. It publishes only by rename and never
// replaces a previous prepared release workspace.
func ComposeProductUpdate(request ComposeProductUpdateRequest) (ComposedProductUpdate, error) {
	composition, err := readComposition(request.CompositionPath)
	if err != nil {
		return ComposedProductUpdate{}, err
	}
	if err := validateComposition(composition); err != nil {
		return ComposedProductUpdate{}, err
	}
	outputDirectory, err := requireNewOutputDirectory(request.OutputDirectory)
	if err != nil {
		return ComposedProductUpdate{}, err
	}
	temporary, err := os.MkdirTemp(filepath.Dir(outputDirectory), "."+filepath.Base(outputDirectory)+".compose-")
	if err != nil {
		return ComposedProductUpdate{}, fmt.Errorf("create temporary Product update workspace: %w", err)
	}
	defer os.RemoveAll(temporary)
	payloadDirectory := filepath.Join(temporary, "payload")
	if err := os.Mkdir(payloadDirectory, 0o700); err != nil {
		return ComposedProductUpdate{}, fmt.Errorf("create payload directory: %w", err)
	}
	nextUpdater, err := copySourceArtifact(composition.NextUpdater, filepath.Join(payloadDirectory, "host-updater"), "next updater", true)
	if err != nil {
		return ComposedProductUpdate{}, err
	}
	nextUpdater.RelativePath = "payload/host-updater"
	nextUpdater.MediaType = "application/octet-stream"
	applyArchiveRelativePath := filepath.ToSlash(filepath.Join("payload", "guest-product-releases", composition.GuestRuntime.ProductRelease.Apply.TargetReleaseID+".tar.gz"))
	applyArchive, err := copySourceArtifact(composition.GuestRuntime.ProductRelease.Apply.Artifact, filepath.Join(temporary, filepath.FromSlash(applyArchiveRelativePath)), "Guest Product apply archive", false)
	if err != nil {
		return ComposedProductUpdate{}, err
	}
	applyArchive.RelativePath = applyArchiveRelativePath
	applyArchive.MediaType = guestReleaseArchiveMedia
	executorRelativePath := filepath.ToSlash(filepath.Join("payload", "effect-executors", composition.GuestRuntime.EffectExecutor.Executor.ID))
	executor, err := copySourceArtifact(composition.GuestRuntime.EffectExecutor.Executor, filepath.Join(temporary, filepath.FromSlash(executorRelativePath)), "Guest Product release effect executor", true)
	if err != nil {
		return ComposedProductUpdate{}, err
	}
	executor.RelativePath = executorRelativePath
	configuration := guestProductReleaseEffectExecutorConfiguration{
		SchemaVersion:    schemaVersion,
		EffectExecutorID: composition.GuestRuntime.EffectExecutor.Executor.ID,
		GuestProductReleaseManagerEndpoint: guestProductReleaseManagerEndpoint{
			Scheme: "http", Host: "127.0.0.1", Port: composition.GuestRuntime.EffectExecutor.GuestProductReleaseManagerPort,
			Path: guestReleaseManagerPath, RequestTimeoutMilliseconds: composition.GuestRuntime.EffectExecutor.RequestTimeoutMilliseconds,
		},
		Apply: intentFromTransition(composition.GuestRuntime.ProductRelease.Apply),
	}
	if composition.GuestRuntime.ProductRelease.Rollback != nil {
		rollbackIntent := intentFromTransition(*composition.GuestRuntime.ProductRelease.Rollback)
		configuration.Rollback = &rollbackIntent
	}
	configurationRelativePath := filepath.ToSlash(filepath.Join("payload", "effect-configurations", composition.GuestRuntime.EffectExecutor.ConfigurationArtifactID+".json"))
	configurationPath := filepath.Join(temporary, filepath.FromSlash(configurationRelativePath))
	if err := writeJSONFile(configurationPath, configuration, 0o600); err != nil {
		return ComposedProductUpdate{}, fmt.Errorf("write Guest Runtime effect configuration: %w", err)
	}
	configurationArtifact, err := artifactFromPath(composition.GuestRuntime.EffectExecutor.ConfigurationArtifactID, configurationRelativePath, configurationPath, effectConfigurationMedia)
	if err != nil {
		return ComposedProductUpdate{}, err
	}
	var rollback productUpdateRollback
	if composition.GuestRuntime.ProductRelease.Rollback == nil {
		rollback = productUpdateRollback{State: "unsupported", Reason: "no immutable prior Guest Product release archive was selected for this bundle"}
	} else {
		rollbackRelativePath := filepath.ToSlash(filepath.Join("payload", "guest-product-releases", composition.GuestRuntime.ProductRelease.Rollback.TargetReleaseID+".tar.gz"))
		rollbackArtifact, copyErr := copySourceArtifact(composition.GuestRuntime.ProductRelease.Rollback.Artifact, filepath.Join(temporary, filepath.FromSlash(rollbackRelativePath)), "Guest Product rollback archive", false)
		if copyErr != nil {
			return ComposedProductUpdate{}, copyErr
		}
		rollbackArtifact.RelativePath = rollbackRelativePath
		rollbackArtifact.MediaType = guestReleaseArchiveMedia
		rollback = productUpdateRollback{State: "available", Artifact: &rollbackArtifact}
	}
	layerPlan := make([]productUpdateLayerPlan, 0, 3)
	layerOrder := make([]string, 0, 3)
	containerEffectConfigurationPath := ""
	if composition.BundledUpstreamImageSet != nil {
		containerLayer, configurationPath, composeErr := composeBundledUpstreamImageSetLayer(*composition.BundledUpstreamImageSet, temporary)
		if composeErr != nil {
			return ComposedProductUpdate{}, composeErr
		}
		layerPlan = append(layerPlan, containerLayer)
		layerOrder = append(layerOrder, "container")
		containerEffectConfigurationPath = configurationPath
	}
	guestDependencies := []string{}
	if composition.BundledUpstreamImageSet != nil {
		guestDependencies = []string{"container"}
	}
	layerPlan = append(layerPlan, productUpdateLayerPlan{
		Layer: "guest-runtime", DependsOn: guestDependencies, Artifact: applyArchive,
		EffectExecutor: productUpdateEffectExecutor{ID: executor.ID, RelativePath: executor.RelativePath, SHA256: executor.SHA256, SizeBytes: executor.SizeBytes, MediaType: effectExecutorMedia, ConfigurationArtifact: configurationArtifact},
		Rollback:       rollback,
	})
	layerOrder = append(layerOrder, "guest-runtime")
	hostPlatformEffectConfigurationPath := ""
	if composition.HostPlatformRelease != nil {
		hostPlatformLayer, configurationPath, composeErr := composeHostPlatformReleaseLayer(
			*composition.HostPlatformRelease,
			composition.Target,
			temporary,
		)
		if composeErr != nil {
			return ComposedProductUpdate{}, composeErr
		}
		layerPlan = append(layerPlan, hostPlatformLayer)
		layerOrder = append(layerOrder, "host-platform")
		hostPlatformEffectConfigurationPath = configurationPath
	}
	specification := productUpdateSpecification{
		SchemaVersion: schemaVersion, ID: composition.SpecificationID, BootstrapEnvelopeID: composition.BundleID, LayerPlan: layerPlan,
	}
	specificationRelativePath := "payload/product-update.json"
	specificationPath := filepath.Join(temporary, filepath.FromSlash(specificationRelativePath))
	if err := writeJSONFile(specificationPath, specification, 0o600); err != nil {
		return ComposedProductUpdate{}, fmt.Errorf("write Product Update Specification: %w", err)
	}
	specificationArtifact, err := artifactFromPath(composition.SpecificationID, specificationRelativePath, specificationPath, "application/json")
	if err != nil {
		return ComposedProductUpdate{}, err
	}
	if nextUpdater.ID == specificationArtifact.ID || nextUpdater.SHA256 == specificationArtifact.SHA256 || nextUpdater.RelativePath == specificationArtifact.RelativePath {
		return ComposedProductUpdate{}, fmt.Errorf("next updater and product update specification must stay distinct")
	}
	signerInput := releaseBundleComposition{
		SchemaVersion: schemaVersion, BundleID: composition.BundleID, ProductID: composition.ProductID, Target: composition.Target, TargetRelease: composition.TargetRelease,
		LayerOrder:    layerOrder,
		NextUpdater:   releaseArtifactDeclaration{ID: nextUpdater.ID, RelativePath: nextUpdater.RelativePath, MediaType: "application/octet-stream"},
		Specification: releaseArtifactDeclaration{ID: specificationArtifact.ID, RelativePath: specificationArtifact.RelativePath, MediaType: specificationArtifact.MediaType},
		SigningKeyID:  composition.SigningKeyID, IssuedAt: composition.IssuedAt,
	}
	signerInputPath := filepath.Join(temporary, "release-bundle-composition.json")
	if err := writeJSONFile(signerInputPath, signerInput, 0o600); err != nil {
		return ComposedProductUpdate{}, fmt.Errorf("write bootstrap release bundle composition: %w", err)
	}
	if err := syncDirectory(payloadDirectory); err != nil {
		return ComposedProductUpdate{}, err
	}
	if err := syncDirectory(temporary); err != nil {
		return ComposedProductUpdate{}, err
	}
	if err := os.Rename(temporary, outputDirectory); err != nil {
		return ComposedProductUpdate{}, fmt.Errorf("publish Guest Product release update workspace: %w", err)
	}
	if err := syncDirectory(filepath.Dir(outputDirectory)); err != nil {
		return ComposedProductUpdate{}, err
	}
	return ComposedProductUpdate{
		OutputDirectory: outputDirectory, PayloadDirectory: filepath.Join(outputDirectory, "payload"),
		ReleaseBundleCompositionPath:   filepath.Join(outputDirectory, "release-bundle-composition.json"),
		ProductUpdateSpecificationPath: filepath.Join(outputDirectory, filepath.FromSlash(specificationRelativePath)),
		EffectConfigurationPath:        filepath.Join(outputDirectory, filepath.FromSlash(configurationRelativePath)),
		ContainerEffectConfigurationPath: func() string {
			if containerEffectConfigurationPath == "" {
				return ""
			}
			return filepath.Join(outputDirectory, filepath.FromSlash(containerEffectConfigurationPath))
		}(),
		HostPlatformEffectConfigurationPath: func() string {
			if hostPlatformEffectConfigurationPath == "" {
				return ""
			}
			return filepath.Join(outputDirectory, filepath.FromSlash(hostPlatformEffectConfigurationPath))
		}(),
	}, nil
}

func composeBundledUpstreamImageSetLayer(source GuestBundledUpstreamImageSetUpdateSource, workspace string) (productUpdateLayerPlan, string, error) {
	applyRelativePath := filepath.ToSlash(filepath.Join("payload", "bundled-upstream-image-sets", source.Apply.TargetImageSetID+".tar.gz"))
	applyArtifact, err := copySourceArtifact(source.Apply.Artifact, filepath.Join(workspace, filepath.FromSlash(applyRelativePath)), "bundled Upstream image-set apply archive", false)
	if err != nil {
		return productUpdateLayerPlan{}, "", err
	}
	applyArtifact.RelativePath = applyRelativePath
	applyArtifact.MediaType = imageSetArchiveMedia
	executorRelativePath := filepath.ToSlash(filepath.Join("payload", "effect-executors", source.EffectExecutor.Executor.ID))
	executor, err := copySourceArtifact(source.EffectExecutor.Executor, filepath.Join(workspace, filepath.FromSlash(executorRelativePath)), "bundled Upstream image-set effect executor", true)
	if err != nil {
		return productUpdateLayerPlan{}, "", err
	}
	executor.RelativePath = executorRelativePath
	configuration := bundledUpstreamImageSetEffectExecutorConfiguration{
		SchemaVersion:    schemaVersion,
		EffectExecutorID: source.EffectExecutor.Executor.ID,
		ImageSetManagerEndpoint: bundledUpstreamImageSetManagerEndpoint{
			Scheme: "http", Host: "127.0.0.1", Port: source.EffectExecutor.ImageSetManagerPort,
			Path: "/v1/bundled-upstream-image-set-updates", RequestTimeoutMilliseconds: source.EffectExecutor.RequestTimeoutMilliseconds,
		},
		Apply: bundledUpstreamImageSetOperationIntent{ExpectedActiveImageSet: source.Apply.ExpectedActiveImageSet, TargetImageSetID: source.Apply.TargetImageSetID},
	}
	if source.Rollback != nil {
		rollbackIntent := bundledUpstreamImageSetOperationIntent{ExpectedActiveImageSet: source.Rollback.ExpectedActiveImageSet, TargetImageSetID: source.Rollback.TargetImageSetID}
		configuration.Rollback = &rollbackIntent
	}
	configurationRelativePath := filepath.ToSlash(filepath.Join("payload", "effect-configurations", source.EffectExecutor.ConfigurationArtifactID+".json"))
	configurationPath := filepath.Join(workspace, filepath.FromSlash(configurationRelativePath))
	if err := writeJSONFile(configurationPath, configuration, 0o600); err != nil {
		return productUpdateLayerPlan{}, "", fmt.Errorf("write Container effect configuration: %w", err)
	}
	configurationArtifact, err := artifactFromPath(source.EffectExecutor.ConfigurationArtifactID, configurationRelativePath, configurationPath, effectConfigurationMedia)
	if err != nil {
		return productUpdateLayerPlan{}, "", err
	}
	rollback := productUpdateRollback{State: "unsupported", Reason: "no immutable prior bundled Upstream image-set archive was selected for this bundle"}
	if source.Rollback != nil {
		rollbackRelativePath := filepath.ToSlash(filepath.Join("payload", "bundled-upstream-image-sets", source.Rollback.TargetImageSetID+".tar.gz"))
		rollbackArtifact, copyErr := copySourceArtifact(source.Rollback.Artifact, filepath.Join(workspace, filepath.FromSlash(rollbackRelativePath)), "bundled Upstream image-set rollback archive", false)
		if copyErr != nil {
			return productUpdateLayerPlan{}, "", copyErr
		}
		rollbackArtifact.RelativePath = rollbackRelativePath
		rollbackArtifact.MediaType = imageSetArchiveMedia
		rollback = productUpdateRollback{State: "available", Artifact: &rollbackArtifact}
	}
	return productUpdateLayerPlan{
		Layer: "container", DependsOn: []string{}, Artifact: applyArtifact,
		EffectExecutor: productUpdateEffectExecutor{ID: executor.ID, RelativePath: executor.RelativePath, SHA256: executor.SHA256, SizeBytes: executor.SizeBytes, MediaType: effectExecutorMedia, ConfigurationArtifact: configurationArtifact},
		Rollback:       rollback,
	}, configurationRelativePath, nil
}

func composeHostPlatformReleaseLayer(source HostPlatformReleaseUpdateSource, target UpdateTarget, workspace string) (productUpdateLayerPlan, string, error) {
	applyRelativePath := filepath.ToSlash(filepath.Join("payload", "host-platform-releases", source.Apply.TargetReleaseID+".tar.gz"))
	applyArtifact, err := copySourceArtifact(source.Apply.Artifact, filepath.Join(workspace, filepath.FromSlash(applyRelativePath)), "Host Platform apply archive", false)
	if err != nil {
		return productUpdateLayerPlan{}, "", err
	}
	applyArtifact.RelativePath = applyRelativePath
	applyArtifact.MediaType = hostPlatformReleaseArchiveMedia
	executorRelativePath := filepath.ToSlash(filepath.Join("payload", "effect-executors", source.EffectExecutor.Executor.ID))
	executor, err := copySourceArtifact(source.EffectExecutor.Executor, filepath.Join(workspace, filepath.FromSlash(executorRelativePath)), "Host Platform release effect executor", true)
	if err != nil {
		return productUpdateLayerPlan{}, "", err
	}
	executor.RelativePath = executorRelativePath
	manager, err := hostInstallationManagerEndpointForTarget(target, source.EffectExecutor.RequestTimeoutMilliseconds)
	if err != nil {
		return productUpdateLayerPlan{}, "", err
	}
	configuration := hostPlatformReleaseEffectExecutorConfiguration{
		SchemaVersion:           schemaVersion,
		EffectExecutorID:        source.EffectExecutor.Executor.ID,
		HostInstallationManager: manager,
		Apply:                   hostPlatformReleaseIntent(source.Apply),
	}
	if source.Rollback != nil {
		rollbackIntent := hostPlatformReleaseIntent(*source.Rollback)
		configuration.Rollback = &rollbackIntent
	}
	configurationRelativePath := filepath.ToSlash(filepath.Join("payload", "effect-configurations", source.EffectExecutor.ConfigurationArtifactID+".json"))
	configurationPath := filepath.Join(workspace, filepath.FromSlash(configurationRelativePath))
	if err := writeJSONFile(configurationPath, configuration, 0o600); err != nil {
		return productUpdateLayerPlan{}, "", fmt.Errorf("write Host Platform release effect configuration: %w", err)
	}
	configurationArtifact, err := artifactFromPath(source.EffectExecutor.ConfigurationArtifactID, configurationRelativePath, configurationPath, effectConfigurationMedia)
	if err != nil {
		return productUpdateLayerPlan{}, "", err
	}
	rollback := productUpdateRollback{State: "unsupported", Reason: "no immutable prior Host Platform release archive was selected for this bundle"}
	if source.Rollback != nil {
		rollbackRelativePath := filepath.ToSlash(filepath.Join("payload", "host-platform-releases", source.Rollback.TargetReleaseID+".tar.gz"))
		rollbackArtifact, copyErr := copySourceArtifact(source.Rollback.Artifact, filepath.Join(workspace, filepath.FromSlash(rollbackRelativePath)), "Host Platform rollback archive", false)
		if copyErr != nil {
			return productUpdateLayerPlan{}, "", copyErr
		}
		rollbackArtifact.RelativePath = rollbackRelativePath
		rollbackArtifact.MediaType = hostPlatformReleaseArchiveMedia
		rollback = productUpdateRollback{State: "available", Artifact: &rollbackArtifact}
	}
	return productUpdateLayerPlan{
		Layer:     "host-platform",
		DependsOn: []string{"guest-runtime"},
		Artifact:  applyArtifact,
		EffectExecutor: productUpdateEffectExecutor{
			ID: executor.ID, RelativePath: executor.RelativePath, SHA256: executor.SHA256, SizeBytes: executor.SizeBytes,
			MediaType: effectExecutorMedia, ConfigurationArtifact: configurationArtifact,
		},
		Rollback: rollback,
	}, configurationRelativePath, nil
}

func hostInstallationManagerEndpointForTarget(target UpdateTarget, timeoutMilliseconds int) (hostInstallationManagerEndpoint, error) {
	switch target.Platform {
	case "macos":
		return hostInstallationManagerEndpoint{
			Platform: target.Platform, ExecutablePath: macOSHostInstallationManagerPath,
			ActiveReleaseManifestPath: macOSActiveReleaseManifestPath, RequestTimeoutMilliseconds: timeoutMilliseconds,
		}, nil
	default:
		return hostInstallationManagerEndpoint{}, fmt.Errorf("Host Platform release composition is unavailable for target platform %q", target.Platform)
	}
}

func hostPlatformReleaseIntent(transition HostPlatformReleaseTransitionSource) hostPlatformReleaseOperationIntent {
	return hostPlatformReleaseOperationIntent{
		ExpectedActiveReleaseID: transition.ExpectedActiveReleaseID,
		TargetReleaseID:         transition.TargetReleaseID,
	}
}

func readComposition(path string) (ProductUpdateComposition, error) {
	contents, err := readRegularFile(path, maximumCompositionBytes)
	if err != nil {
		return ProductUpdateComposition{}, fmt.Errorf("read Product update composition: %w", err)
	}
	decoder := json.NewDecoder(strings.NewReader(string(contents)))
	decoder.DisallowUnknownFields()
	var composition ProductUpdateComposition
	if err := decoder.Decode(&composition); err != nil {
		return ProductUpdateComposition{}, fmt.Errorf("decode Product update composition: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return ProductUpdateComposition{}, fmt.Errorf("Product update composition must contain exactly one JSON object")
	}
	return composition, nil
}

func validateComposition(composition ProductUpdateComposition) error {
	if composition.SchemaVersion != schemaVersion || !validIdentifier(composition.BundleID) || !validIdentifier(composition.ProductID) || !validIdentifier(composition.SigningKeyID) || !validIdentifier(composition.SpecificationID) || composition.Target.Platform != "macos" || composition.Target.Architecture != "arm64" || composition.TargetRelease.ProductVersion == "" || composition.TargetRelease.RuntimeVersion == "" || composition.IssuedAt == "" {
		return fmt.Errorf("Product update identity or current macOS arm64 target is invalid")
	}
	if err := validateSourceArtifact(composition.NextUpdater, "next updater", true); err != nil {
		return err
	}
	if err := validateTransition(composition.GuestRuntime.ProductRelease.Apply, "apply"); err != nil {
		return err
	}
	if composition.GuestRuntime.ProductRelease.Rollback != nil {
		if err := validateTransition(*composition.GuestRuntime.ProductRelease.Rollback, "rollback"); err != nil {
			return err
		}
		if composition.GuestRuntime.ProductRelease.Rollback.ExpectedActiveReleaseID != composition.GuestRuntime.ProductRelease.Apply.TargetReleaseID || composition.GuestRuntime.ProductRelease.Rollback.TargetReleaseID != composition.GuestRuntime.ProductRelease.Apply.ExpectedActiveReleaseID {
			return fmt.Errorf("Guest Product rollback transition must reverse the selected apply transition")
		}
	}
	if err := validateSourceArtifact(composition.GuestRuntime.EffectExecutor.Executor, "Guest Product release effect executor", true); err != nil {
		return err
	}
	if !validIdentifier(composition.GuestRuntime.EffectExecutor.ConfigurationArtifactID) || composition.GuestRuntime.EffectExecutor.ConfigurationArtifactID == composition.GuestRuntime.EffectExecutor.Executor.ID || composition.GuestRuntime.EffectExecutor.GuestProductReleaseManagerPort < 1 || composition.GuestRuntime.EffectExecutor.GuestProductReleaseManagerPort > 65535 || composition.GuestRuntime.EffectExecutor.RequestTimeoutMilliseconds < 1 || composition.GuestRuntime.EffectExecutor.RequestTimeoutMilliseconds > 900000 {
		return fmt.Errorf("Guest Runtime effect executor configuration identity or Host-loopback endpoint is invalid")
	}
	ids := []string{composition.NextUpdater.ID, composition.SpecificationID, composition.GuestRuntime.ProductRelease.Apply.Artifact.ID, composition.GuestRuntime.EffectExecutor.Executor.ID, composition.GuestRuntime.EffectExecutor.ConfigurationArtifactID}
	if composition.GuestRuntime.ProductRelease.Rollback != nil {
		ids = append(ids, composition.GuestRuntime.ProductRelease.Rollback.Artifact.ID)
	}
	if composition.BundledUpstreamImageSet != nil {
		if err := validateBundledUpstreamImageSetUpdate(*composition.BundledUpstreamImageSet); err != nil {
			return err
		}
		ids = append(ids,
			composition.BundledUpstreamImageSet.Apply.Artifact.ID,
			composition.BundledUpstreamImageSet.EffectExecutor.Executor.ID,
			composition.BundledUpstreamImageSet.EffectExecutor.ConfigurationArtifactID,
		)
		if composition.BundledUpstreamImageSet.Rollback != nil {
			ids = append(ids, composition.BundledUpstreamImageSet.Rollback.Artifact.ID)
		}
	}
	if composition.HostPlatformRelease != nil {
		if err := validateHostPlatformReleaseUpdate(*composition.HostPlatformRelease); err != nil {
			return err
		}
		ids = append(ids,
			composition.HostPlatformRelease.Apply.Artifact.ID,
			composition.HostPlatformRelease.EffectExecutor.Executor.ID,
			composition.HostPlatformRelease.EffectExecutor.ConfigurationArtifactID,
		)
		if composition.HostPlatformRelease.Rollback != nil {
			ids = append(ids, composition.HostPlatformRelease.Rollback.Artifact.ID)
		}
	}
	seenIDs := map[string]bool{}
	for _, id := range ids {
		if seenIDs[id] {
			return fmt.Errorf("bootstrap and Product Update Specification artifact identities must be distinct across all selected layers")
		}
		seenIDs[id] = true
	}
	return nil
}

func validateHostPlatformReleaseUpdate(source HostPlatformReleaseUpdateSource) error {
	if err := validateHostPlatformReleaseTransition(source.Apply, "apply"); err != nil {
		return err
	}
	if source.Rollback != nil {
		if err := validateHostPlatformReleaseTransition(*source.Rollback, "rollback"); err != nil {
			return err
		}
		if source.Rollback.ExpectedActiveReleaseID != source.Apply.TargetReleaseID || source.Rollback.TargetReleaseID != source.Apply.ExpectedActiveReleaseID {
			return fmt.Errorf("Host Platform rollback transition must reverse the selected apply transition")
		}
	}
	if err := validateSourceArtifact(source.EffectExecutor.Executor, "Host Platform release effect executor", true); err != nil {
		return err
	}
	if !validIdentifier(source.EffectExecutor.ConfigurationArtifactID) ||
		source.EffectExecutor.ConfigurationArtifactID == source.EffectExecutor.Executor.ID ||
		source.EffectExecutor.RequestTimeoutMilliseconds < 1 ||
		source.EffectExecutor.RequestTimeoutMilliseconds > 900000 {
		return fmt.Errorf("Host Platform release effect executor configuration identity or timeout is invalid")
	}
	return nil
}

func validateHostPlatformReleaseTransition(transition HostPlatformReleaseTransitionSource, action string) error {
	if !validIdentifier(transition.ExpectedActiveReleaseID) ||
		!validIdentifier(transition.TargetReleaseID) ||
		transition.ExpectedActiveReleaseID == transition.TargetReleaseID {
		return fmt.Errorf("Host Platform %s release transition is invalid", action)
	}
	return validateSourceArtifact(transition.Artifact, "Host Platform "+action+" archive", false)
}

func validateTransition(transition GuestProductReleaseTransitionSource, action string) error {
	if !validIdentifier(transition.ExpectedActiveReleaseID) || !validIdentifier(transition.TargetReleaseID) || transition.ExpectedActiveReleaseID == transition.TargetReleaseID || transition.TargetReleaseDirectory != guestProductReleaseRoot+transition.TargetReleaseID {
		return fmt.Errorf("Guest Product %s release IDs or release directory are invalid", action)
	}
	return validateSourceArtifact(transition.Artifact, "Guest Product "+action+" archive", false)
}

func validateBundledUpstreamImageSetUpdate(source GuestBundledUpstreamImageSetUpdateSource) error {
	if err := validateBundledUpstreamImageSetTransition(source.Apply, "apply"); err != nil {
		return err
	}
	if source.Rollback != nil {
		if source.Apply.ExpectedActiveImageSet.State != "active" {
			return fmt.Errorf("bundled Upstream image-set rollback is unavailable when apply starts unprovisioned")
		}
		if err := validateBundledUpstreamImageSetTransition(*source.Rollback, "rollback"); err != nil {
			return err
		}
		if source.Rollback.ExpectedActiveImageSet.State != "active" || source.Rollback.ExpectedActiveImageSet.ImageSetID != source.Apply.TargetImageSetID || source.Rollback.TargetImageSetID != source.Apply.ExpectedActiveImageSet.ImageSetID {
			return fmt.Errorf("bundled Upstream image-set rollback must reverse the selected apply transition")
		}
	}
	if err := validateSourceArtifact(source.EffectExecutor.Executor, "bundled Upstream image-set effect executor", true); err != nil {
		return err
	}
	if !validIdentifier(source.EffectExecutor.ConfigurationArtifactID) || source.EffectExecutor.ConfigurationArtifactID == source.EffectExecutor.Executor.ID || source.EffectExecutor.ImageSetManagerPort < 1 || source.EffectExecutor.ImageSetManagerPort > 65535 || source.EffectExecutor.RequestTimeoutMilliseconds < 1 || source.EffectExecutor.RequestTimeoutMilliseconds > 900000 {
		return fmt.Errorf("Container effect executor configuration identity or Host-loopback endpoint is invalid")
	}
	return nil
}

func validateBundledUpstreamImageSetTransition(transition GuestBundledUpstreamImageSetTransitionSource, action string) error {
	if err := validateActiveImageSetSelection(transition.ExpectedActiveImageSet); err != nil || !validIdentifier(transition.TargetImageSetID) {
		return fmt.Errorf("bundled Upstream image-set %s transition is invalid", action)
	}
	if transition.ExpectedActiveImageSet.State == "active" && transition.ExpectedActiveImageSet.ImageSetID == transition.TargetImageSetID {
		return fmt.Errorf("bundled Upstream image-set %s target cannot equal the expected active image set", action)
	}
	return validateSourceArtifact(transition.Artifact, "bundled Upstream image-set "+action+" archive", false)
}

func validateActiveImageSetSelection(selection activeImageSetSelection) error {
	switch selection.State {
	case "unprovisioned":
		if selection.ImageSetID != "" {
			return fmt.Errorf("unprovisioned bundled Upstream image-set selection cannot name an image set")
		}
	case "active":
		if !validIdentifier(selection.ImageSetID) {
			return fmt.Errorf("active bundled Upstream image-set selection requires an image set id")
		}
	default:
		return fmt.Errorf("bundled Upstream image-set selection state is unsupported")
	}
	return nil
}

func validateSourceArtifact(artifact SourceArtifact, description string, requireExecutable bool) error {
	if !validIdentifier(artifact.ID) || artifact.SourcePath == "" || !filepath.IsAbs(artifact.SourcePath) {
		return fmt.Errorf("%s identity and absolute source path are required", description)
	}
	info, err := os.Lstat(artifact.SourcePath)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || info.Size() < 1 {
		return fmt.Errorf("%s source must be a non-empty regular non-symlink file", description)
	}
	if requireExecutable && info.Mode().Perm()&0o111 == 0 {
		return fmt.Errorf("%s source must be executable", description)
	}
	return nil
}

func copySourceArtifact(source SourceArtifact, outputPath string, description string, requireExecutable bool) (payloadArtifact, error) {
	if err := validateSourceArtifact(source, description, requireExecutable); err != nil {
		return payloadArtifact{}, err
	}
	if err := os.MkdirAll(filepath.Dir(outputPath), 0o700); err != nil {
		return payloadArtifact{}, fmt.Errorf("create %s output directory: %w", description, err)
	}
	sourceFile, err := os.Open(source.SourcePath)
	if err != nil {
		return payloadArtifact{}, fmt.Errorf("open %s source: %w", description, err)
	}
	defer sourceFile.Close()
	info, err := sourceFile.Stat()
	if err != nil || !info.Mode().IsRegular() || info.Size() < 1 {
		return payloadArtifact{}, fmt.Errorf("inspect %s source: source changed or is not regular", description)
	}
	temporary, err := os.CreateTemp(filepath.Dir(outputPath), "."+filepath.Base(outputPath)+".copy-")
	if err != nil {
		return payloadArtifact{}, fmt.Errorf("create %s output: %w", description, err)
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	hash := sha256.New()
	count, copyErr := io.Copy(io.MultiWriter(temporary, hash), sourceFile)
	if closeErr := temporary.Close(); copyErr != nil {
		return payloadArtifact{}, fmt.Errorf("copy %s source: %w", description, copyErr)
	} else if closeErr != nil {
		return payloadArtifact{}, fmt.Errorf("close %s output: %w", description, closeErr)
	}
	if count != info.Size() {
		return payloadArtifact{}, fmt.Errorf("%s source changed while it was copied", description)
	}
	mode := info.Mode().Perm()
	if err := os.Chmod(temporaryPath, mode); err != nil {
		return payloadArtifact{}, fmt.Errorf("set %s output mode: %w", description, err)
	}
	if err := os.Rename(temporaryPath, outputPath); err != nil {
		return payloadArtifact{}, fmt.Errorf("publish %s payload artifact: %w", description, err)
	}
	return payloadArtifact{ID: source.ID, SHA256: hex.EncodeToString(hash.Sum(nil)), SizeBytes: count}, nil
}

func artifactFromPath(id string, relativePath string, path string, mediaType string) (payloadArtifact, error) {
	contents, err := readRegularFile(path, -1)
	if err != nil {
		return payloadArtifact{}, fmt.Errorf("read generated payload artifact: %w", err)
	}
	digest := sha256.Sum256(contents)
	return payloadArtifact{ID: id, RelativePath: relativePath, SHA256: hex.EncodeToString(digest[:]), SizeBytes: int64(len(contents)), MediaType: mediaType}, nil
}

func intentFromTransition(transition GuestProductReleaseTransitionSource) guestProductReleaseOperationIntent {
	return guestProductReleaseOperationIntent{ExpectedActiveReleaseID: transition.ExpectedActiveReleaseID, TargetReleaseID: transition.TargetReleaseID, TargetReleaseDirectory: transition.TargetReleaseDirectory}
}

func requireNewOutputDirectory(path string) (string, error) {
	if path == "" || !filepath.IsAbs(path) {
		return "", fmt.Errorf("output directory must be an absolute new path")
	}
	output, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	if _, err := os.Lstat(output); err == nil {
		return "", fmt.Errorf("Product update output already exists: %s", output)
	} else if !errors.Is(err, os.ErrNotExist) {
		return "", fmt.Errorf("inspect Product update output: %w", err)
	}
	parent := filepath.Dir(output)
	info, err := os.Lstat(parent)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return "", fmt.Errorf("Product update output parent must be an existing non-symlink directory")
	}
	return output, nil
}

func readRegularFile(path string, maximumBytes int64) ([]byte, error) {
	if path == "" || !filepath.IsAbs(path) {
		return nil, fmt.Errorf("path must be absolute")
	}
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return nil, fmt.Errorf("file is missing, not regular, or a symlink")
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	limit := maximumBytes
	if limit < 0 {
		limit = info.Size()
	}
	contents, err := io.ReadAll(io.LimitReader(file, limit+1))
	if err != nil {
		return nil, err
	}
	if int64(len(contents)) > limit {
		return nil, fmt.Errorf("file exceeds maximum size")
	}
	return contents, nil
}

func writeJSONFile(path string, value any, mode os.FileMode) error {
	contents, err := json.Marshal(value)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	temporary, err := os.CreateTemp(filepath.Dir(path), "."+filepath.Base(path)+".write-")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if _, err := temporary.Write(contents); err != nil {
		temporary.Close()
		return err
	}
	if err := temporary.Sync(); err != nil {
		temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	if err := os.Chmod(temporaryPath, mode); err != nil {
		return err
	}
	return os.Rename(temporaryPath, path)
}

func syncDirectory(path string) error {
	directory, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("open directory for sync: %w", err)
	}
	defer directory.Close()
	if err := directory.Sync(); err != nil {
		return fmt.Errorf("sync directory: %w", err)
	}
	return nil
}

func validIdentifier(value string) bool { return identifierPattern.MatchString(value) }
