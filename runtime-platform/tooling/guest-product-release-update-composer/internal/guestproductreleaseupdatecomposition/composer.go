// Package guestproductreleaseupdatecomposition owns release-process-only
// preparation of the concrete Guest Product C26 payload. It does not sign C25,
// activate Guest state, or interpret a staged Host update.
package guestproductreleaseupdatecomposition

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
	schemaVersion            = "v1"
	guestReleaseArchiveMedia = "application/vnd.tirosh.vitalserver.guest-product-release+tar+gzip"
	effectExecutorMedia      = "application/vnd.tirosh.vitalserver.update-layer-effect-executor"
	effectConfigurationMedia = "application/vnd.tirosh.vitalserver.update-layer-effect-configuration+json"
	imageSetArchiveMedia     = "application/vnd.tirosh.vitalserver.bundled-upstream-image-set+tar+gzip"
	maximumCompositionBytes  = 1 << 20
	guestProductReleaseRoot  = "/opt/vitalserver/releases/"
	guestReleaseManagerPath  = "/v1/guest-product-release-updates"
)

var identifierPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$`)

// GuestProductReleaseUpdateComposition is a build-local release selection
// document. Source paths are intentionally not a C25/C26 contract: they are
// consumed only by this release tool and never leave the trusted release
// workspace. Resulting C25, C26, and C61 documents carry immutable IDs,
// digests, sizes, and payload-relative locations instead.
type GuestProductReleaseUpdateComposition struct {
	SchemaVersion       string                                  `json:"schemaVersion"`
	BundleID            string                                  `json:"bundleId"`
	ProductID           string                                  `json:"productId"`
	Target              UpdateTarget                            `json:"target"`
	TargetRelease       TargetRelease                           `json:"targetRelease"`
	SigningKeyID        string                                  `json:"signingKeyId"`
	IssuedAt            string                                  `json:"issuedAt"`
	SpecificationID     string                                  `json:"specificationId"`
	NextUpdater         SourceArtifact                          `json:"nextUpdater"`
	GuestProductRelease GuestProductReleaseUpdateSource         `json:"guestProductRelease"`
	EffectExecutor      GuestProductReleaseEffectExecutorSource `json:"effectExecutor"`
	// BundledUpstreamImageSet is optional because an external-Upstream release
	// has no Guest-owned Container layer. When present it is always emitted
	// before the Guest Product layer in C25/C26.
	BundledUpstreamImageSet *GuestBundledUpstreamImageSetUpdateSource `json:"bundledUpstreamImageSet,omitempty"`
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
// C66. It names immutable archive and C55 executable bytes, while the actual
// selected active image-set remains a C64 compare-and-swap input.
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

type ComposeGuestProductReleaseUpdateRequest struct {
	CompositionPath string
	OutputDirectory string
}

// ComposedGuestProductReleaseUpdate contains the prepared inputs to the
// generic signer. The generic signer remains the sole owner of C25 signing.
type ComposedGuestProductReleaseUpdate struct {
	OutputDirectory                  string `json:"outputDirectory"`
	PayloadDirectory                 string `json:"payloadDirectory"`
	ReleaseBundleCompositionPath     string `json:"releaseBundleCompositionPath"`
	ProductUpdateSpecificationPath   string `json:"productUpdateSpecificationPath"`
	EffectConfigurationPath          string `json:"effectConfigurationPath"`
	ContainerEffectConfigurationPath string `json:"containerEffectConfigurationPath,omitempty"`
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

// ComposeGuestProductReleaseUpdate copies selected immutable source bytes,
// derives C26 integrity declarations from the copied payload, writes C61, and
// emits a C25 signer input. It publishes only by rename and never replaces a
// previous prepared release workspace.
func ComposeGuestProductReleaseUpdate(request ComposeGuestProductReleaseUpdateRequest) (ComposedGuestProductReleaseUpdate, error) {
	composition, err := readComposition(request.CompositionPath)
	if err != nil {
		return ComposedGuestProductReleaseUpdate{}, err
	}
	if err := validateComposition(composition); err != nil {
		return ComposedGuestProductReleaseUpdate{}, err
	}
	outputDirectory, err := requireNewOutputDirectory(request.OutputDirectory)
	if err != nil {
		return ComposedGuestProductReleaseUpdate{}, err
	}
	temporary, err := os.MkdirTemp(filepath.Dir(outputDirectory), "."+filepath.Base(outputDirectory)+".compose-")
	if err != nil {
		return ComposedGuestProductReleaseUpdate{}, fmt.Errorf("create temporary Guest Product release update workspace: %w", err)
	}
	defer os.RemoveAll(temporary)
	payloadDirectory := filepath.Join(temporary, "payload")
	if err := os.Mkdir(payloadDirectory, 0o700); err != nil {
		return ComposedGuestProductReleaseUpdate{}, fmt.Errorf("create payload directory: %w", err)
	}
	nextUpdater, err := copySourceArtifact(composition.NextUpdater, filepath.Join(payloadDirectory, "host-updater"), "next updater", true)
	if err != nil {
		return ComposedGuestProductReleaseUpdate{}, err
	}
	nextUpdater.RelativePath = "payload/host-updater"
	nextUpdater.MediaType = "application/octet-stream"
	applyArchiveRelativePath := filepath.ToSlash(filepath.Join("payload", "guest-product-releases", composition.GuestProductRelease.Apply.TargetReleaseID+".tar.gz"))
	applyArchive, err := copySourceArtifact(composition.GuestProductRelease.Apply.Artifact, filepath.Join(temporary, filepath.FromSlash(applyArchiveRelativePath)), "Guest Product apply archive", false)
	if err != nil {
		return ComposedGuestProductReleaseUpdate{}, err
	}
	applyArchive.RelativePath = applyArchiveRelativePath
	applyArchive.MediaType = guestReleaseArchiveMedia
	executorRelativePath := filepath.ToSlash(filepath.Join("payload", "effect-executors", composition.EffectExecutor.Executor.ID))
	executor, err := copySourceArtifact(composition.EffectExecutor.Executor, filepath.Join(temporary, filepath.FromSlash(executorRelativePath)), "Guest Product release effect executor", true)
	if err != nil {
		return ComposedGuestProductReleaseUpdate{}, err
	}
	executor.RelativePath = executorRelativePath
	configuration := guestProductReleaseEffectExecutorConfiguration{
		SchemaVersion:    schemaVersion,
		EffectExecutorID: composition.EffectExecutor.Executor.ID,
		GuestProductReleaseManagerEndpoint: guestProductReleaseManagerEndpoint{
			Scheme: "http", Host: "127.0.0.1", Port: composition.EffectExecutor.GuestProductReleaseManagerPort,
			Path: guestReleaseManagerPath, RequestTimeoutMilliseconds: composition.EffectExecutor.RequestTimeoutMilliseconds,
		},
		Apply: intentFromTransition(composition.GuestProductRelease.Apply),
	}
	if composition.GuestProductRelease.Rollback != nil {
		rollbackIntent := intentFromTransition(*composition.GuestProductRelease.Rollback)
		configuration.Rollback = &rollbackIntent
	}
	configurationRelativePath := filepath.ToSlash(filepath.Join("payload", "effect-configurations", composition.EffectExecutor.ConfigurationArtifactID+".json"))
	configurationPath := filepath.Join(temporary, filepath.FromSlash(configurationRelativePath))
	if err := writeJSONFile(configurationPath, configuration, 0o600); err != nil {
		return ComposedGuestProductReleaseUpdate{}, fmt.Errorf("write C61 Guest Product release effect configuration: %w", err)
	}
	configurationArtifact, err := artifactFromPath(composition.EffectExecutor.ConfigurationArtifactID, configurationRelativePath, configurationPath, effectConfigurationMedia)
	if err != nil {
		return ComposedGuestProductReleaseUpdate{}, err
	}
	var rollback productUpdateRollback
	if composition.GuestProductRelease.Rollback == nil {
		rollback = productUpdateRollback{State: "unsupported", Reason: "no immutable prior Guest Product release archive was selected for this bundle"}
	} else {
		rollbackRelativePath := filepath.ToSlash(filepath.Join("payload", "guest-product-releases", composition.GuestProductRelease.Rollback.TargetReleaseID+".tar.gz"))
		rollbackArtifact, copyErr := copySourceArtifact(composition.GuestProductRelease.Rollback.Artifact, filepath.Join(temporary, filepath.FromSlash(rollbackRelativePath)), "Guest Product rollback archive", false)
		if copyErr != nil {
			return ComposedGuestProductReleaseUpdate{}, copyErr
		}
		rollbackArtifact.RelativePath = rollbackRelativePath
		rollbackArtifact.MediaType = guestReleaseArchiveMedia
		rollback = productUpdateRollback{State: "available", Artifact: &rollbackArtifact}
	}
	layerPlan := make([]productUpdateLayerPlan, 0, 2)
	layerOrder := make([]string, 0, 2)
	containerEffectConfigurationPath := ""
	if composition.BundledUpstreamImageSet != nil {
		containerLayer, configurationPath, composeErr := composeBundledUpstreamImageSetLayer(*composition.BundledUpstreamImageSet, temporary)
		if composeErr != nil {
			return ComposedGuestProductReleaseUpdate{}, composeErr
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
	specification := productUpdateSpecification{
		SchemaVersion: schemaVersion, ID: composition.SpecificationID, BootstrapEnvelopeID: composition.BundleID, LayerPlan: layerPlan,
	}
	specificationRelativePath := "payload/product-update.json"
	specificationPath := filepath.Join(temporary, filepath.FromSlash(specificationRelativePath))
	if err := writeJSONFile(specificationPath, specification, 0o600); err != nil {
		return ComposedGuestProductReleaseUpdate{}, fmt.Errorf("write C26 product update specification: %w", err)
	}
	specificationArtifact, err := artifactFromPath(composition.SpecificationID, specificationRelativePath, specificationPath, "application/json")
	if err != nil {
		return ComposedGuestProductReleaseUpdate{}, err
	}
	if nextUpdater.ID == specificationArtifact.ID || nextUpdater.SHA256 == specificationArtifact.SHA256 || nextUpdater.RelativePath == specificationArtifact.RelativePath {
		return ComposedGuestProductReleaseUpdate{}, fmt.Errorf("next updater and product update specification must stay distinct")
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
		return ComposedGuestProductReleaseUpdate{}, fmt.Errorf("write C25 release bundle composition: %w", err)
	}
	if err := syncDirectory(payloadDirectory); err != nil {
		return ComposedGuestProductReleaseUpdate{}, err
	}
	if err := syncDirectory(temporary); err != nil {
		return ComposedGuestProductReleaseUpdate{}, err
	}
	if err := os.Rename(temporary, outputDirectory); err != nil {
		return ComposedGuestProductReleaseUpdate{}, fmt.Errorf("publish Guest Product release update workspace: %w", err)
	}
	if err := syncDirectory(filepath.Dir(outputDirectory)); err != nil {
		return ComposedGuestProductReleaseUpdate{}, err
	}
	return ComposedGuestProductReleaseUpdate{
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
		return productUpdateLayerPlan{}, "", fmt.Errorf("write C66 bundled Upstream image-set effect configuration: %w", err)
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

func readComposition(path string) (GuestProductReleaseUpdateComposition, error) {
	contents, err := readRegularFile(path, maximumCompositionBytes)
	if err != nil {
		return GuestProductReleaseUpdateComposition{}, fmt.Errorf("read Guest Product release update composition: %w", err)
	}
	decoder := json.NewDecoder(strings.NewReader(string(contents)))
	decoder.DisallowUnknownFields()
	var composition GuestProductReleaseUpdateComposition
	if err := decoder.Decode(&composition); err != nil {
		return GuestProductReleaseUpdateComposition{}, fmt.Errorf("decode Guest Product release update composition: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return GuestProductReleaseUpdateComposition{}, fmt.Errorf("Guest Product release update composition must contain exactly one JSON object")
	}
	return composition, nil
}

func validateComposition(composition GuestProductReleaseUpdateComposition) error {
	if composition.SchemaVersion != schemaVersion || !validIdentifier(composition.BundleID) || !validIdentifier(composition.ProductID) || !validIdentifier(composition.SigningKeyID) || !validIdentifier(composition.SpecificationID) || composition.Target.Platform != "macos" || composition.Target.Architecture != "arm64" || composition.TargetRelease.ProductVersion == "" || composition.TargetRelease.RuntimeVersion == "" || composition.IssuedAt == "" {
		return fmt.Errorf("Guest Product release update identity or current macOS arm64 target is invalid")
	}
	if err := validateSourceArtifact(composition.NextUpdater, "next updater", true); err != nil {
		return err
	}
	if err := validateTransition(composition.GuestProductRelease.Apply, "apply"); err != nil {
		return err
	}
	if composition.GuestProductRelease.Rollback != nil {
		if err := validateTransition(*composition.GuestProductRelease.Rollback, "rollback"); err != nil {
			return err
		}
		if composition.GuestProductRelease.Rollback.ExpectedActiveReleaseID != composition.GuestProductRelease.Apply.TargetReleaseID || composition.GuestProductRelease.Rollback.TargetReleaseID != composition.GuestProductRelease.Apply.ExpectedActiveReleaseID {
			return fmt.Errorf("Guest Product rollback transition must reverse the selected apply transition")
		}
	}
	if err := validateSourceArtifact(composition.EffectExecutor.Executor, "Guest Product release effect executor", true); err != nil {
		return err
	}
	if !validIdentifier(composition.EffectExecutor.ConfigurationArtifactID) || composition.EffectExecutor.ConfigurationArtifactID == composition.EffectExecutor.Executor.ID || composition.EffectExecutor.GuestProductReleaseManagerPort < 1 || composition.EffectExecutor.GuestProductReleaseManagerPort > 65535 || composition.EffectExecutor.RequestTimeoutMilliseconds < 1 || composition.EffectExecutor.RequestTimeoutMilliseconds > 900000 {
		return fmt.Errorf("Guest Product release effect executor configuration identity or C32 endpoint is invalid")
	}
	ids := []string{composition.NextUpdater.ID, composition.SpecificationID, composition.GuestProductRelease.Apply.Artifact.ID, composition.EffectExecutor.Executor.ID, composition.EffectExecutor.ConfigurationArtifactID}
	if composition.GuestProductRelease.Rollback != nil {
		ids = append(ids, composition.GuestProductRelease.Rollback.Artifact.ID)
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
	seenIDs := map[string]bool{}
	for _, id := range ids {
		if seenIDs[id] {
			return fmt.Errorf("C25/C26 artifact identities must be distinct across all selected update layers")
		}
		seenIDs[id] = true
	}
	return nil
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
		return fmt.Errorf("bundled Upstream image-set effect executor configuration identity or C32 endpoint is invalid")
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
		return "", fmt.Errorf("Guest Product release update output already exists: %s", output)
	} else if !errors.Is(err, os.ErrNotExist) {
		return "", fmt.Errorf("inspect Guest Product release update output: %w", err)
	}
	parent := filepath.Dir(output)
	info, err := os.Lstat(parent)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return "", fmt.Errorf("Guest Product release update output parent must be an existing non-symlink directory")
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
