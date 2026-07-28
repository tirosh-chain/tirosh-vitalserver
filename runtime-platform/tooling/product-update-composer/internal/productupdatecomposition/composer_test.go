package productupdatecomposition

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestComposeProductUpdatePreparesGuestRuntimeLayerAndBootstrapSignerInput(t *testing.T) {
	request, composition, root := validCompositionRequest(t)
	result, err := ComposeProductUpdate(request)
	if err != nil {
		t.Fatalf("compose Product update: %v", err)
	}
	if result.OutputDirectory != request.OutputDirectory || result.PayloadDirectory != filepath.Join(request.OutputDirectory, "payload") {
		t.Fatalf("unexpected composition result: %+v", result)
	}
	if contents, readErr := os.ReadFile(filepath.Join(result.PayloadDirectory, "host-updater")); readErr != nil || string(contents) != "host-updater-030" {
		t.Fatalf("next updater payload was not copied readErr=%v contents=%q", readErr, contents)
	}
	var specification productUpdateSpecification
	decodeFile(t, result.ProductUpdateSpecificationPath, &specification)
	if specification.ID != composition.SpecificationID || specification.BootstrapEnvelopeID != composition.BundleID || len(specification.LayerPlan) != 1 {
		t.Fatalf("unexpected Product Update Specification: %+v", specification)
	}
	layer := specification.LayerPlan[0]
	if layer.Layer != "guest-runtime" || layer.Artifact.ID != composition.GuestRuntime.ProductRelease.Apply.Artifact.ID || layer.Artifact.RelativePath != "payload/guest-product-releases/vitalserver-guest-product-0.3.0.tar.gz" || layer.Artifact.MediaType != guestReleaseArchiveMedia {
		t.Fatalf("unexpected Guest Runtime apply layer: %+v", layer)
	}
	if layer.Rollback.State != "available" || layer.Rollback.Artifact == nil || layer.Rollback.Artifact.ID != composition.GuestRuntime.ProductRelease.Rollback.Artifact.ID {
		t.Fatalf("rollback archive was not selected explicitly: %+v", layer.Rollback)
	}
	if layer.EffectExecutor.ID != composition.GuestRuntime.EffectExecutor.Executor.ID || layer.EffectExecutor.MediaType != effectExecutorMedia || layer.EffectExecutor.ConfigurationArtifact.ID != composition.GuestRuntime.EffectExecutor.ConfigurationArtifactID || layer.EffectExecutor.ConfigurationArtifact.MediaType != effectConfigurationMedia {
		t.Fatalf("unexpected Guest Runtime effect executor: %+v", layer.EffectExecutor)
	}
	var configuration guestProductReleaseEffectExecutorConfiguration
	decodeFile(t, result.EffectConfigurationPath, &configuration)
	if configuration.EffectExecutorID != composition.GuestRuntime.EffectExecutor.Executor.ID || configuration.GuestProductReleaseManagerEndpoint.Host != "127.0.0.1" || configuration.GuestProductReleaseManagerEndpoint.Port != 18444 || configuration.Apply.TargetReleaseID != composition.GuestRuntime.ProductRelease.Apply.TargetReleaseID || configuration.Rollback == nil || configuration.Rollback.TargetReleaseID != composition.GuestRuntime.ProductRelease.Rollback.TargetReleaseID {
		t.Fatalf("unexpected Guest Runtime effect configuration: %+v", configuration)
	}
	configurationBytes, err := os.ReadFile(result.EffectConfigurationPath)
	if err != nil {
		t.Fatal(err)
	}
	configurationDigest := sha256.Sum256(configurationBytes)
	if layer.EffectExecutor.ConfigurationArtifact.SHA256 != hex.EncodeToString(configurationDigest[:]) || layer.EffectExecutor.ConfigurationArtifact.SizeBytes != int64(len(configurationBytes)) {
		t.Fatalf("Guest Runtime configuration integrity did not derive from written bytes: %+v", layer.EffectExecutor.ConfigurationArtifact)
	}
	var signerInput releaseBundleComposition
	decodeFile(t, result.ReleaseBundleCompositionPath, &signerInput)
	if signerInput.BundleID != composition.BundleID || signerInput.NextUpdater.RelativePath != "payload/host-updater" || signerInput.Specification.RelativePath != "payload/product-update.json" || signerInput.LayerOrder[0] != "guest-runtime" {
		t.Fatalf("unexpected bootstrap signer input: %+v", signerInput)
	}
	if _, err := os.Stat(filepath.Join(root, "prepared")); err != nil {
		t.Fatalf("prepared output was not atomically published: %v", err)
	}
}

func TestComposeProductUpdateRejectsNonReversingRollbackBeforeCreatingOutput(t *testing.T) {
	request, composition, _ := validCompositionRequest(t)
	composition.GuestRuntime.ProductRelease.Rollback.ExpectedActiveReleaseID = "not-the-apply-target"
	writeComposition(t, request.CompositionPath, composition)
	if _, err := ComposeProductUpdate(request); err == nil {
		t.Fatal("expected non-reversing rollback to be rejected")
	}
	if _, err := os.Lstat(request.OutputDirectory); !os.IsNotExist(err) {
		t.Fatalf("invalid release composition created output err=%v", err)
	}
}

func TestComposeProductUpdateRejectsSymlinkedReleaseArchive(t *testing.T) {
	request, composition, root := validCompositionRequest(t)
	archivePath := filepath.Join(root, "artifacts", "linked-guest-release.tar.gz")
	if err := os.Symlink(composition.GuestRuntime.ProductRelease.Apply.Artifact.SourcePath, archivePath); err != nil {
		t.Fatal(err)
	}
	composition.GuestRuntime.ProductRelease.Apply.Artifact.SourcePath = archivePath
	writeComposition(t, request.CompositionPath, composition)
	if _, err := ComposeProductUpdate(request); err == nil {
		t.Fatal("expected symlinked Guest archive to be rejected")
	}
}

func TestComposeProductUpdatePlacesBundledUpstreamContainerBeforeGuestRuntime(t *testing.T) {
	request, composition, root := validCompositionRequest(t)
	artifacts := filepath.Join(root, "artifacts")
	apply := writeArtifact(t, artifacts, "bundled-upstream-030.tar.gz", "bundled-upstream-030", 0o600)
	rollback := writeArtifact(t, artifacts, "bundled-upstream-020.tar.gz", "bundled-upstream-020", 0o600)
	executor := writeArtifact(t, artifacts, "bundled-upstream-effect-executor", "bundled-upstream-effect-executor-030", 0o700)
	composition.BundledUpstreamImageSet = &GuestBundledUpstreamImageSetUpdateSource{
		Apply: GuestBundledUpstreamImageSetTransitionSource{
			ExpectedActiveImageSet: activeImageSetSelection{State: "active", ImageSetID: "bundled-upstream-020"},
			TargetImageSetID:       "bundled-upstream-030",
			Artifact:               SourceArtifact{ID: "bundled-upstream-image-set-030", SourcePath: apply},
		},
		Rollback: &GuestBundledUpstreamImageSetTransitionSource{
			ExpectedActiveImageSet: activeImageSetSelection{State: "active", ImageSetID: "bundled-upstream-030"},
			TargetImageSetID:       "bundled-upstream-020",
			Artifact:               SourceArtifact{ID: "bundled-upstream-image-set-020", SourcePath: rollback},
		},
		EffectExecutor: GuestBundledUpstreamImageSetEffectExecutorSource{
			Executor:                   SourceArtifact{ID: "bundled-upstream-effect-executor-030", SourcePath: executor},
			ConfigurationArtifactID:    "bundled-upstream-effect-configuration-030",
			ImageSetManagerPort:        18445,
			RequestTimeoutMilliseconds: 600000,
		},
	}
	writeComposition(t, request.CompositionPath, composition)
	result, err := ComposeProductUpdate(request)
	if err != nil {
		t.Fatalf("compose bundled Upstream update: %v", err)
	}
	var specification productUpdateSpecification
	decodeFile(t, result.ProductUpdateSpecificationPath, &specification)
	if len(specification.LayerPlan) != 2 || specification.LayerPlan[0].Layer != "container" || specification.LayerPlan[1].Layer != "guest-runtime" || len(specification.LayerPlan[1].DependsOn) != 1 || specification.LayerPlan[1].DependsOn[0] != "container" {
		t.Fatalf("Product Update Specification did not preserve Container-before-Guest order: %+v", specification.LayerPlan)
	}
	container := specification.LayerPlan[0]
	if container.Artifact.MediaType != imageSetArchiveMedia || container.Artifact.RelativePath != "payload/bundled-upstream-image-sets/bundled-upstream-030.tar.gz" || container.EffectExecutor.ID != composition.BundledUpstreamImageSet.EffectExecutor.Executor.ID || container.Rollback.State != "available" {
		t.Fatalf("unexpected Container layer: %+v", container)
	}
	if result.ContainerEffectConfigurationPath == "" {
		t.Fatal("expected Container effect configuration output path")
	}
	var configuration bundledUpstreamImageSetEffectExecutorConfiguration
	decodeFile(t, result.ContainerEffectConfigurationPath, &configuration)
	if configuration.EffectExecutorID != composition.BundledUpstreamImageSet.EffectExecutor.Executor.ID || configuration.ImageSetManagerEndpoint.Host != "127.0.0.1" || configuration.ImageSetManagerEndpoint.Port != 18445 || configuration.Apply.TargetImageSetID != "bundled-upstream-030" || configuration.Rollback == nil || configuration.Rollback.TargetImageSetID != "bundled-upstream-020" {
		t.Fatalf("unexpected Container effect configuration: %+v", configuration)
	}
	var signerInput releaseBundleComposition
	decodeFile(t, result.ReleaseBundleCompositionPath, &signerInput)
	if len(signerInput.LayerOrder) != 2 || signerInput.LayerOrder[0] != "container" || signerInput.LayerOrder[1] != "guest-runtime" {
		t.Fatalf("unexpected bootstrap layer order: %+v", signerInput.LayerOrder)
	}
}

func TestComposeProductUpdatePlacesHostPlatformLast(t *testing.T) {
	request, composition, root := validCompositionRequest(t)
	artifacts := filepath.Join(root, "artifacts")
	containerApply := writeArtifact(t, artifacts, "bundled-upstream-030.tar.gz", "bundled-upstream-030", 0o600)
	containerExecutor := writeArtifact(t, artifacts, "bundled-upstream-effect-executor", "bundled-upstream-effect-executor-030", 0o700)
	hostApply := writeArtifact(t, artifacts, "host-platform-030.tar.gz", "host-platform-030", 0o600)
	hostRollback := writeArtifact(t, artifacts, "host-platform-020.tar.gz", "host-platform-020", 0o600)
	hostExecutor := writeArtifact(t, artifacts, "host-platform-release-effect-executor", "host-platform-release-effect-executor-030", 0o700)
	composition.BundledUpstreamImageSet = &GuestBundledUpstreamImageSetUpdateSource{
		Apply:          GuestBundledUpstreamImageSetTransitionSource{ExpectedActiveImageSet: activeImageSetSelection{State: "unprovisioned"}, TargetImageSetID: "bundled-upstream-030", Artifact: SourceArtifact{ID: "bundled-upstream-image-set-030", SourcePath: containerApply}},
		EffectExecutor: GuestBundledUpstreamImageSetEffectExecutorSource{Executor: SourceArtifact{ID: "bundled-upstream-effect-executor-030", SourcePath: containerExecutor}, ConfigurationArtifactID: "bundled-upstream-effect-configuration-030", ImageSetManagerPort: 18445, RequestTimeoutMilliseconds: 600000},
	}
	composition.HostPlatformRelease = &HostPlatformReleaseUpdateSource{
		Apply: HostPlatformReleaseTransitionSource{
			ExpectedActiveReleaseID: "runtime-platform-020",
			TargetReleaseID:         "runtime-platform-030",
			Artifact:                SourceArtifact{ID: "host-platform-release-030", SourcePath: hostApply},
		},
		Rollback: &HostPlatformReleaseTransitionSource{
			ExpectedActiveReleaseID: "runtime-platform-030",
			TargetReleaseID:         "runtime-platform-020",
			Artifact:                SourceArtifact{ID: "host-platform-release-020", SourcePath: hostRollback},
		},
		EffectExecutor: HostPlatformReleaseEffectExecutorSource{
			Executor:                   SourceArtifact{ID: "host-platform-release-effect-executor-030", SourcePath: hostExecutor},
			ConfigurationArtifactID:    "host-platform-release-effect-configuration-030",
			RequestTimeoutMilliseconds: 300000,
		},
	}
	writeComposition(t, request.CompositionPath, composition)

	result, err := ComposeProductUpdate(request)
	if err != nil {
		t.Fatalf("compose complete Product update: %v", err)
	}
	var specification productUpdateSpecification
	decodeFile(t, result.ProductUpdateSpecificationPath, &specification)
	if len(specification.LayerPlan) != 3 {
		t.Fatalf("expected complete three-layer plan: %+v", specification.LayerPlan)
	}
	if specification.LayerPlan[0].Layer != "container" || specification.LayerPlan[1].Layer != "guest-runtime" || specification.LayerPlan[2].Layer != "host-platform" {
		t.Fatalf("Host Platform must be the final layer: %+v", specification.LayerPlan)
	}
	hostLayer := specification.LayerPlan[2]
	if len(hostLayer.DependsOn) != 1 || hostLayer.DependsOn[0] != "guest-runtime" || hostLayer.Artifact.MediaType != hostPlatformReleaseArchiveMedia || hostLayer.Rollback.State != "available" || hostLayer.Rollback.Artifact == nil {
		t.Fatalf("unexpected Host Platform layer: %+v", hostLayer)
	}
	var configuration hostPlatformReleaseEffectExecutorConfiguration
	decodeFile(t, result.HostPlatformEffectConfigurationPath, &configuration)
	if configuration.HostInstallationManager.Platform != "macos" ||
		configuration.HostInstallationManager.ExecutablePath != "/Library/Application Support/VitalServerRuntimePlatform/current/bin/host-installation-manager" ||
		configuration.HostInstallationManager.ActiveReleaseManifestPath != "/Library/Application Support/VitalServerRuntimePlatform/current/installation-manifest.json" ||
		configuration.Apply.ExpectedActiveReleaseID != "runtime-platform-020" ||
		configuration.Apply.TargetReleaseID != "runtime-platform-030" ||
		configuration.Rollback == nil ||
		configuration.Rollback.TargetReleaseID != "runtime-platform-020" {
		t.Fatalf("unexpected Host Platform effect configuration: %+v", configuration)
	}
	var signerInput releaseBundleComposition
	decodeFile(t, result.ReleaseBundleCompositionPath, &signerInput)
	if len(signerInput.LayerOrder) != 3 || signerInput.LayerOrder[0] != "container" || signerInput.LayerOrder[1] != "guest-runtime" || signerInput.LayerOrder[2] != "host-platform" {
		t.Fatalf("unexpected complete Product layer order: %+v", signerInput.LayerOrder)
	}
}

func TestComposeProductUpdateRejectsNonReversingHostPlatformRollback(t *testing.T) {
	request, composition, root := validCompositionRequest(t)
	artifacts := filepath.Join(root, "artifacts")
	hostApply := writeArtifact(t, artifacts, "host-platform-030.tar.gz", "host-platform-030", 0o600)
	hostRollback := writeArtifact(t, artifacts, "host-platform-020.tar.gz", "host-platform-020", 0o600)
	hostExecutor := writeArtifact(t, artifacts, "host-platform-release-effect-executor", "host-platform-release-effect-executor-030", 0o700)
	composition.HostPlatformRelease = &HostPlatformReleaseUpdateSource{
		Apply:    HostPlatformReleaseTransitionSource{ExpectedActiveReleaseID: "runtime-platform-020", TargetReleaseID: "runtime-platform-030", Artifact: SourceArtifact{ID: "host-platform-release-030", SourcePath: hostApply}},
		Rollback: &HostPlatformReleaseTransitionSource{ExpectedActiveReleaseID: "runtime-platform-030", TargetReleaseID: "different-release", Artifact: SourceArtifact{ID: "host-platform-release-020", SourcePath: hostRollback}},
		EffectExecutor: HostPlatformReleaseEffectExecutorSource{
			Executor: SourceArtifact{ID: "host-platform-release-effect-executor-030", SourcePath: hostExecutor}, ConfigurationArtifactID: "host-platform-release-effect-configuration-030", RequestTimeoutMilliseconds: 300000,
		},
	}
	writeComposition(t, request.CompositionPath, composition)
	if _, err := ComposeProductUpdate(request); err == nil {
		t.Fatal("expected non-reversing Host Platform rollback to be rejected")
	}
	if _, err := os.Lstat(request.OutputDirectory); !os.IsNotExist(err) {
		t.Fatalf("invalid Host Platform release composition created output err=%v", err)
	}
}

func TestComposeProductUpdateRejectsUnprovisionedContainerRollback(t *testing.T) {
	request, composition, root := validCompositionRequest(t)
	artifacts := filepath.Join(root, "artifacts")
	apply := writeArtifact(t, artifacts, "bundled-upstream-030.tar.gz", "bundled-upstream-030", 0o600)
	rollback := writeArtifact(t, artifacts, "bundled-upstream-020.tar.gz", "bundled-upstream-020", 0o600)
	executor := writeArtifact(t, artifacts, "bundled-upstream-effect-executor", "bundled-upstream-effect-executor-030", 0o700)
	composition.BundledUpstreamImageSet = &GuestBundledUpstreamImageSetUpdateSource{
		Apply:          GuestBundledUpstreamImageSetTransitionSource{ExpectedActiveImageSet: activeImageSetSelection{State: "unprovisioned"}, TargetImageSetID: "bundled-upstream-030", Artifact: SourceArtifact{ID: "bundled-upstream-image-set-030", SourcePath: apply}},
		Rollback:       &GuestBundledUpstreamImageSetTransitionSource{ExpectedActiveImageSet: activeImageSetSelection{State: "active", ImageSetID: "bundled-upstream-030"}, TargetImageSetID: "bundled-upstream-020", Artifact: SourceArtifact{ID: "bundled-upstream-image-set-020", SourcePath: rollback}},
		EffectExecutor: GuestBundledUpstreamImageSetEffectExecutorSource{Executor: SourceArtifact{ID: "bundled-upstream-effect-executor-030", SourcePath: executor}, ConfigurationArtifactID: "bundled-upstream-effect-configuration-030", ImageSetManagerPort: 18445, RequestTimeoutMilliseconds: 600000},
	}
	writeComposition(t, request.CompositionPath, composition)
	if _, err := ComposeProductUpdate(request); err == nil {
		t.Fatal("expected unprovisioned image-set rollback rejection")
	}
}

func validCompositionRequest(t *testing.T) (ComposeProductUpdateRequest, ProductUpdateComposition, string) {
	t.Helper()
	root := t.TempDir()
	artifacts := filepath.Join(root, "artifacts")
	if err := os.Mkdir(artifacts, 0o700); err != nil {
		t.Fatal(err)
	}
	updater := writeArtifact(t, artifacts, "host-updater", "host-updater-030", 0o700)
	apply := writeArtifact(t, artifacts, "guest-product-030.tar.gz", "guest-product-030", 0o600)
	rollback := writeArtifact(t, artifacts, "guest-product-020.tar.gz", "guest-product-020", 0o600)
	executor := writeArtifact(t, artifacts, "guest-product-release-effect-executor", "guest-product-release-effect-executor-030", 0o700)
	composition := ProductUpdateComposition{
		SchemaVersion: "v1", BundleID: "release-bootstrap-030", ProductID: "vitalserver-runtime-platform",
		Target: UpdateTarget{Platform: "macos", Architecture: "arm64"}, TargetRelease: TargetRelease{ProductVersion: "0.3.0", RuntimeVersion: "0.3.0"},
		SigningKeyID: "release-key-2026", IssuedAt: "2026-07-20T00:00:00Z", SpecificationID: "product-update-030",
		NextUpdater: SourceArtifact{ID: "host-updater-030", SourcePath: updater},
		GuestRuntime: GuestRuntimeUpdateSource{
			ProductRelease: GuestProductReleaseUpdateSource{
				Apply:    GuestProductReleaseTransitionSource{ExpectedActiveReleaseID: "vitalserver-guest-product-0.2.0", TargetReleaseID: "vitalserver-guest-product-0.3.0", TargetReleaseDirectory: "/opt/vitalserver/releases/vitalserver-guest-product-0.3.0", Artifact: SourceArtifact{ID: "guest-product-release-030", SourcePath: apply}},
				Rollback: &GuestProductReleaseTransitionSource{ExpectedActiveReleaseID: "vitalserver-guest-product-0.3.0", TargetReleaseID: "vitalserver-guest-product-0.2.0", TargetReleaseDirectory: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0", Artifact: SourceArtifact{ID: "guest-product-release-020", SourcePath: rollback}},
			},
			EffectExecutor: GuestProductReleaseEffectExecutorSource{Executor: SourceArtifact{ID: "guest-product-release-effect-executor-030", SourcePath: executor}, ConfigurationArtifactID: "guest-product-release-effect-executor-configuration-030", GuestProductReleaseManagerPort: 18444, RequestTimeoutMilliseconds: 600000},
		},
	}
	compositionPath := filepath.Join(root, "product-update-composition.json")
	writeComposition(t, compositionPath, composition)
	return ComposeProductUpdateRequest{CompositionPath: compositionPath, OutputDirectory: filepath.Join(root, "prepared")}, composition, root
}

func writeComposition(t *testing.T, path string, composition ProductUpdateComposition) {
	t.Helper()
	contents, err := json.Marshal(composition)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, contents, 0o600); err != nil {
		t.Fatal(err)
	}
}

func writeArtifact(t *testing.T, directory string, name string, contents string, mode os.FileMode) string {
	t.Helper()
	path := filepath.Join(directory, name)
	if err := os.WriteFile(path, []byte(contents), mode); err != nil {
		t.Fatal(err)
	}
	return path
}

func decodeFile(t *testing.T, path string, target any) {
	t.Helper()
	contents, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(contents, target); err != nil {
		t.Fatal(err)
	}
}
