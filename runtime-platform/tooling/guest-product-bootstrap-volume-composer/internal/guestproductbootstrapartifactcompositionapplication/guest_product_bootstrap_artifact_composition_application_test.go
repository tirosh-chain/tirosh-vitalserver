package guestproductbootstrapartifactcompositionapplication_test

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"

	diskfs "github.com/diskfs/go-diskfs"
	"github.com/diskfs/go-diskfs/filesystem"
	"github.com/diskfs/go-diskfs/filesystem/iso9660"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-bootstrap-volume-composer/internal/guestproductbootstrapartifactcompositionapplication"
)

func TestExecuteGuestProductBootstrapArtifactCompositionCopiesRootAndCreatesBootstrapVolume(t *testing.T) {
	root := t.TempDir()
	inputRoot := filepath.Join(root, "input")
	outputDirectory := filepath.Join(root, "output")
	if err := os.MkdirAll(inputRoot, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(outputDirectory, 0o700); err != nil {
		t.Fatal(err)
	}
	artifacts := map[string]testInputArtifact{}
	writeArtifact := func(identifier, relativePath string, contents []byte) testInputArtifact {
		path := filepath.Join(inputRoot, filepath.FromSlash(relativePath))
		if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, contents, 0o600); err != nil {
			t.Fatal(err)
		}
		digest := sha256.Sum256(contents)
		artifact := testInputArtifact{ID: identifier, InputRelativePath: relativePath, SizeBytes: int64(len(contents)), SHA256: hex.EncodeToString(digest[:])}
		artifacts[identifier] = artifact
		return artifact
	}
	writeArtifact("linux-arm64-kernel", "inputs/boot/Image", []byte("kernel"))
	writeArtifact("linux-arm64-initrd", "inputs/boot/initrd.img", []byte("initrd"))
	writeArtifact("guest-runtime-linux-arm64", "inputs/services/guest-runtime", []byte("guest-runtime"))
	telemetryCollector := []byte("guest-telemetry-collector")
	telemetryCollectorConfiguration := []byte("receivers: {}\n")
	writeArtifact("guest-telemetry-collector-linux-arm64", "inputs/services/guest-telemetry-collector", telemetryCollector)
	writeArtifact("guest-telemetry-collector-configuration", "inputs/configuration/guest-telemetry-collector.yaml", telemetryCollectorConfiguration)
	writeArtifact("guest-node-services-linux-arm64", "inputs/services/guest-node-services.tar.gz", guestNodeServicesArchive(t))
	writeArtifact("guest-product-process-supervisor-linux-arm64", "inputs/services/guest-product-process-supervisor", []byte("process-supervisor"))
	writeArtifact("guest-product-release-manager-linux-arm64", "inputs/services/guest-product-release-manager", []byte("release-manager"))
	writeArtifact("guest-product-release-manager-configuration", "inputs/configuration/guest-product-release-manager.json", []byte(`{"schemaVersion":"v1","managerId":"release-manager","listener":{"bindHost":"127.0.0.1","port":18444},"releaseDirectoryRoot":"/opt/vitalserver/releases","currentReleaseLinkPath":"/opt/vitalserver/current","stagingDirectory":"/var/lib/vitalserver/guest-product-releases/staging","stateDirectory":"/var/lib/vitalserver/guest-product-releases","stateDirectoryMode":"0700","maximumReleaseArtifactBytes":1024,"serviceManagement":{"systemctlExecutablePath":"/usr/bin/systemctl","managedServiceUnitName":"vitalserver-guest-product.service","restartTimeoutMilliseconds":1000},"healthCheck":{"scheme":"http","host":"127.0.0.1","port":18443,"path":"/v1/runtime/readiness","acceptedStatusCodes":[200],"timeoutMilliseconds":1000}}`))
	const releaseDirectory = "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev"
	const currentReleaseDirectory = "/opt/vitalserver/current"
	processDeploymentConfiguration := strings.ReplaceAll(`{"schemaVersion":"v1","deploymentId":"guest-product","requiredProcessExitPolicy":"terminate-guest-product","guestRuntime":{"executablePath":"/opt/vitalserver/bin/guest-runtime","stateDatabasePath":"/var/lib/vitalserver/guest-runtime/guest-runtime.sqlite","recorderCatalogDatabaseUrlMaterialPath":"/var/lib/vitalserver/private/recorder-catalog-database-url","recorderCatalogMigrationReceiptPath":"/var/lib/vitalserver/private/recorder-catalog-migration-receipt.json","recorderCatalogAdmissionBearerTokenMaterialPath":"/var/lib/vitalserver/private/recorder-catalog-admission-token","recorderObservationMaxReportAgeSeconds":300,"archiveSourceAdmissionBearerTokenMaterialPath":"/var/lib/vitalserver/private/archive-source-admission-token","archiveArtifactObjectRootDirectory":"/var/lib/vitalserver/archive-artifacts","archiveSourceMaximumBytes":67108864,"labReplaySourceObjectRootDirectory":"/var/lib/vitalserver/lab-replay-sources","labReplaySourceMaximumBytes":67108864,"labReplaySpoolRootDirectory":"/var/lib/vitalserver/lab-replay-spools","labReplayStringTrackPolicy":"skip","labReplayGapPolicy":"fail-frame","labReplayFrameBatchSize":1,"recorderAttributionPolicyKind":"recorder-assignment-owner","operationalStateBackup":{"rootDirectory":"/var/lib/vitalserver/guest-runtime","ledgerDatabasePath":"/var/lib/vitalserver/guest-runtime/operational-state-backup-ledger.sqlite","destinationReference":{"resourceType":"guest-backup-destination","resourceId":"guest-local-operational-state"},"pgDumpExecutablePath":"/usr/bin/pg_dump","pgRestoreExecutablePath":"/usr/bin/pg_restore"},"archiveExportProvider":{"kind":"vitalserver-indexed-library","credentialMaterialPath":"/var/lib/vitalserver/private/external-vitalserver-primary-library.json","vitalServerConfiguration":{"kind":"external-vitalserver-delivery-configuration","configurationPath":"/etc/vitalserver/external-vitalserver-delivery-configuration.json"}}},"recorderGateway":{"nodeExecutablePath":"/opt/vitalserver/node/bin/node","programPath":"/opt/vitalserver/recorder-gateway/dist/cmd/recorder-gateway.js","vitalServerTopologyDeploymentPath":"/etc/vitalserver/guest-product-vitalserver-topology-deployment.json","externalVitalServerDeliveryConfigurationPath":"/etc/vitalserver/external-vitalserver-delivery-configuration.json","guestRuntimeObservationCatalogEndpoint":"http://127.0.0.1:18443","observationCatalogBearerTokenMaterialPath":"/var/lib/vitalserver/private/recorder-catalog-admission-token","vitalUploadPolicy":{"maximumBytes":67108864},"guestRuntimeArchiveSourceAdmissionEndpoint":"http://127.0.0.1:18443/internal/v1/archive/recorder-uploads","archiveSourceAdmissionBearerTokenMaterialPath":"/var/lib/vitalserver/private/archive-source-admission-token"},"labRecorderRunner":{"nodeExecutablePath":"/opt/vitalserver/node/bin/node","programPath":"/opt/vitalserver/lab-recorder-runner/dist/cmd/lab-recorder-runner.js","scenarioCatalogPath":"/opt/vitalserver/lab-recorder-runner/lab-scenario-catalog.json","replayStateDirectory":"/var/lib/vitalserver/lab-replay-runner"},"telemetryCollector":{"executablePath":"/opt/vitalserver/bin/guest-telemetry-collector","configurationPath":"/etc/vitalserver/guest-telemetry-collector.yaml"}}`, "/opt/vitalserver/", currentReleaseDirectory+"/")
	processDeploymentConfiguration = strings.ReplaceAll(processDeploymentConfiguration, "/etc/vitalserver/", currentReleaseDirectory+"/config/")
	writeArtifact("guest-product-process-deployment-configuration", "inputs/configuration/guest-product-process-deployment.json", []byte(processDeploymentConfiguration))
	serviceManagerDeploymentConfiguration := strings.ReplaceAll(`{"schemaVersion":"v1","serviceManagerKind":"systemd","serviceUnitName":"vitalserver-guest-product.service","supervisor":{"executablePath":"/opt/vitalserver/bin/guest-product-process-supervisor","deploymentConfigurationPath":"/etc/vitalserver/guest-product-process-deployment.json"},"restart":{"mode":"on-failure","delayMilliseconds":1000},"logging":{"standardOutput":"journal+console","standardError":"journal+console"},"install":{"wantedByTarget":"multi-user.target"}}`, "/opt/vitalserver/", currentReleaseDirectory+"/")
	serviceManagerDeploymentConfiguration = strings.ReplaceAll(serviceManagerDeploymentConfiguration, "/etc/vitalserver/", currentReleaseDirectory+"/config/")
	writeArtifact("guest-product-service-manager-deployment-configuration", "inputs/configuration/guest-product-service-manager-deployment.json", []byte(serviceManagerDeploymentConfiguration))
	bootstrapConfiguration := strings.ReplaceAll(`{"schemaVersion":"v1","bootstrapId":"vitalserver-guest-product-bootstrap","volumeLabel":"CIDATA","guestBootstrapVolumeFileSystem":"iso9660","instanceId":"guest-bootstrap","localHostName":"vitalserver-guest","guestArchitecture":"arm64","guestRuntime":{"artifactId":"guest-runtime-linux-arm64","destinationPath":"/opt/vitalserver/bin/guest-runtime","fileMode":"0755"},"guestRuntimeStateDirectory":{"directoryPath":"/var/lib/vitalserver/guest-runtime","directoryMode":"0700"},"guestPrivateStateDirectory":{"directoryPath":"/var/lib/vitalserver/private","directoryMode":"0700"},"guestArchiveArtifactObjectDirectory":{"directoryPath":"/var/lib/vitalserver/archive-artifacts","directoryMode":"0700"},"guestRecorderCatalogPostgreSQL":{"packageManager":"apt","packageNames":["postgresql","python3-alembic","python3-psycopg"],"serviceName":"postgresql.service","databaseHost":"127.0.0.1","databasePort":5432,"databaseName":"vitalserver","databaseRoleName":"vitalserver","databaseURLMaterialPath":"/var/lib/vitalserver/private/recorder-catalog-database-url","catalogAdmissionBearerTokenMaterialPath":"/var/lib/vitalserver/private/recorder-catalog-admission-token","archiveSourceAdmissionBearerTokenMaterialPath":"/var/lib/vitalserver/private/archive-source-admission-token","generatedSecretByteCount":32,"migrationExecutablePath":"/opt/vitalserver/current/bin/guest-runtime","migrationPythonExecutablePath":"/usr/bin/python3","expectedRevision":"0006_backup_owner","migrationReceiptPath":"/var/lib/vitalserver/private/recorder-catalog-migration-receipt.json"},"guestTelemetryCollector":{"artifactId":"guest-telemetry-collector-linux-arm64","destinationPath":"/opt/vitalserver/bin/guest-telemetry-collector","fileMode":"0755"},"guestTelemetryCollectorConfiguration":{"artifactId":"guest-telemetry-collector-configuration","destinationPath":"/etc/vitalserver/guest-telemetry-collector.yaml","fileMode":"0644"},"guestTelemetryStateDirectory":{"directoryPath":"/var/lib/vitalserver/telemetry","directoryMode":"0700"},"guestNodeServicesBundle":{"artifactId":"guest-node-services-linux-arm64","archiveFormat":"tar-gzip","entryModePolicy":"preserve-archive-mode","symbolicLinkPolicy":"allow-relative-links-to-declared-regular-files","destinationDirectory":"/opt/vitalserver","requiredArchivePaths":["node/bin/node","recorder-gateway/dist/cmd/recorder-gateway.js","lab-recorder-runner/dist/cmd/lab-recorder-runner.js","lab-recorder-runner/lab-scenario-catalog.json"]},"guestProductProcessSupervisor":{"artifactId":"guest-product-process-supervisor-linux-arm64","destinationPath":"/opt/vitalserver/bin/guest-product-process-supervisor","fileMode":"0755"},"guestProductProcessDeployment":{"artifactId":"guest-product-process-deployment-configuration","destinationPath":"/etc/vitalserver/guest-product-process-deployment.json","fileMode":"0644"},"guestProductVitalServerTopologyDeployment":{"artifactId":"guest-product-vitalserver-topology-deployment","destinationPath":"/etc/vitalserver/guest-product-vitalserver-topology-deployment.json","fileMode":"0644"},"externalVitalServerDeliveryConfiguration":{"artifactId":"external-vitalserver-delivery-configuration","destinationPath":"/etc/vitalserver/external-vitalserver-delivery-configuration.json","fileMode":"0644"},"guestProductServiceManagerDeployment":{"artifactId":"guest-product-service-manager-deployment-configuration","configurationDestinationPath":"/etc/vitalserver/guest-product-service-manager-deployment.json","unitDestinationPath":"/etc/systemd/system/vitalserver-guest-product.service","enabledUnitLinkPath":"/etc/systemd/system/multi-user.target.wants/vitalserver-guest-product.service","enabledUnitLinkTargetPath":"/etc/systemd/system/vitalserver-guest-product.service"}}`, "/opt/vitalserver/", releaseDirectory+"/")
	bootstrapConfiguration = strings.ReplaceAll(bootstrapConfiguration, releaseDirectory+"/current/", currentReleaseDirectory+"/")
	bootstrapConfiguration = strings.Replace(bootstrapConfiguration, `"destinationDirectory":"/opt/vitalserver"`, `"destinationDirectory":"`+releaseDirectory+`"`, 1)
	bootstrapConfiguration = strings.ReplaceAll(bootstrapConfiguration, "/etc/vitalserver/", releaseDirectory+"/config/")
	bootstrapConfiguration = strings.Replace(bootstrapConfiguration, `"localHostName":"vitalserver-guest",`, `"localHostName":"vitalserver-guest","guestProductRelease":{"releaseId":"vitalserver-guest-product-0.2.0-dev","releaseDirectory":"`+releaseDirectory+`","currentReleaseLinkPath":"`+currentReleaseDirectory+`","releaseStateDirectory":"/var/lib/vitalserver/guest-product-releases","releaseStateDirectoryMode":"0700"},`, 1)
	bootstrapConfiguration = strings.Replace(bootstrapConfiguration, `"guestProductServiceManagerDeployment":`, `"guestProductReleaseManager":{"executable":{"artifactId":"guest-product-release-manager-linux-arm64","destinationPath":"`+releaseDirectory+`/bin/guest-product-release-manager","fileMode":"0755"},"configuration":{"artifactId":"guest-product-release-manager-configuration","destinationPath":"`+releaseDirectory+`/config/guest-product-release-manager.json","fileMode":"0644"},"serviceUnit":{"serviceUnitName":"vitalserver-guest-product-release-manager.service","unitDestinationPath":"/etc/systemd/system/vitalserver-guest-product-release-manager.service","enabledUnitLinkPath":"/etc/systemd/system/multi-user.target.wants/vitalserver-guest-product-release-manager.service","enabledUnitLinkTargetPath":"/etc/systemd/system/vitalserver-guest-product-release-manager.service","restart":{"mode":"on-failure","delayMilliseconds":1000},"logging":{"standardOutput":"journal+console","standardError":"journal+console"},"install":{"wantedByTarget":"multi-user.target"}}},"guestProductServiceManagerDeployment":`, 1)
	writeArtifact("guest-product-bootstrap-configuration", "inputs/configuration/guest-product-bootstrap.json", []byte(bootstrapConfiguration))
	writeArtifact("guest-product-vitalserver-topology-deployment", "inputs/configuration/guest-product-vitalserver-topology-deployment.json", []byte(`{"schemaVersion":"v1","topologyDeploymentId":"external-vitalserver-primary-topology","topologyKind":"external-vitalserver","vitalServerDeliveryProvider":{"kind":"external-vitalserver","id":"external-vitalserver-primary","capabilityRevision":1},"publicBrowserExposure":"not-exposed","externalVitalServerDeploymentConfiguration":{"externalUpstreamIntegrationReference":{"resourceType":"external-upstream-integration","resourceId":"external-vitalserver-primary"},"externalVitalServerDeliveryConfigurationReference":{"resourceType":"external-vitalserver-delivery-configuration","resourceId":"external-vitalserver-primary-delivery"}}}`))
	// C46 is copied as the exact Administrator-owned configuration byte into
	// the final NoCloud volume. Include every current C46 capability here so a
	// newly added contract field cannot be rejected by the strict C35 decoder
	// or silently lost before the Guest can consume it.
	externalVitalServerDeliveryConfiguration := []byte(`{"schemaVersion":"v1","configurationId":"external-vitalserver-primary-delivery","externalUpstreamIntegrationReference":{"resourceType":"external-upstream-integration","resourceId":"external-vitalserver-primary"},"vitalServerDeliveryProvider":{"kind":"external-vitalserver","id":"external-vitalserver-primary","capabilityRevision":1},"vitalServerPacketDeliveryEndpoint":{"scheme":"https","host":"vitalserver.external.example","port":443},"vitalServerDeliveryAcknowledgementTimeoutMilliseconds":1000,"vitalServerObservationEndpoint":{"scheme":"https","host":"vitalserver.external.example","port":443,"path":"/healthz","acceptedStatusCodes":[200]},"vitalServerArchiveProvider":{"kind":"vitalserver-indexed-library","id":"external-vitalserver-primary-library","capabilityRevision":1},"vitalServerIndexedLibraryEndpoint":{"scheme":"https","host":"vitalserver.external.example","port":443},"vitalServerArchiveCredentialReference":{"kind":"vitalserver-library-credential","id":"external-vitalserver-primary-library"},"vitalServerArchiveRequestTimeoutMilliseconds":10000}`)
	writeArtifact("external-vitalserver-delivery-configuration", "inputs/configuration/external-vitalserver-delivery-configuration.json", externalVitalServerDeliveryConfiguration)
	rootBytes := []byte("immutable-declared-root-storage")
	writeArtifact("linux-arm64-root-storage-base", "inputs/storage/guest-root.raw", rootBytes)

	command := map[string]any{
		"schemaVersion": "v1", "compilationId": "guest-artifact-composition-test", "artifactSetId": "guest-artifact-set", "architecture": "arm64",
		"buildEnvironment":     map[string]any{"id": "guest-product-bootstrap-artifact-composer", "builderExecutableSizeBytes": 1, "builderExecutableSHA256": stringsOf("a", 64)},
		"boot":                 map[string]any{"kernel": map[string]any{"source": artifacts["linux-arm64-kernel"], "outputRelativePath": "boot/Image"}, "initialRamdisk": map[string]any{"source": artifacts["linux-arm64-initrd"], "outputRelativePath": "boot/initrd.img"}},
		"guestRuntimeArtifact": artifacts["guest-runtime-linux-arm64"], "guestTelemetryCollectorArtifact": artifacts["guest-telemetry-collector-linux-arm64"], "guestTelemetryCollectorConfigurationArtifact": artifacts["guest-telemetry-collector-configuration"], "guestNodeServicesArtifact": artifacts["guest-node-services-linux-arm64"],
		"guestProductProcessSupervisorArtifact": artifacts["guest-product-process-supervisor-linux-arm64"], "guestProductProcessDeploymentConfigurationArtifact": artifacts["guest-product-process-deployment-configuration"], "guestProductReleaseManagerArtifact": artifacts["guest-product-release-manager-linux-arm64"], "guestProductReleaseManagerConfigurationArtifact": artifacts["guest-product-release-manager-configuration"], "guestProductServiceManagerDeploymentConfigurationArtifact": artifacts["guest-product-service-manager-deployment-configuration"], "guestProductBootstrapConfigurationArtifact": artifacts["guest-product-bootstrap-configuration"], "guestProductVitalServerTopologyDeploymentArtifact": artifacts["guest-product-vitalserver-topology-deployment"], "externalVitalServerDeliveryConfigurationArtifact": artifacts["external-vitalserver-delivery-configuration"],
		"storageDevices": []any{
			map[string]any{"id": "guest-root", "role": "guest-root-storage", "storageImageFormat": "raw", "readOnly": false, "baseImage": artifacts["linux-arm64-root-storage-base"], "outputRelativePath": "storage/guest-root.raw"},
			map[string]any{"id": "guest-product-bootstrap", "role": "guest-product-bootstrap-volume", "storageImageFormat": "raw", "guestVolumeFileSystem": "iso9660", "readOnly": true, "outputRelativePath": "storage/guest-product-bootstrap.raw"},
		},
	}
	commandBytes, err := json.Marshal(command)
	if err != nil {
		t.Fatal(err)
	}
	commandPath := filepath.Join(root, "guest-artifact-compilation-command.json")
	if err := os.WriteFile(commandPath, commandBytes, 0o600); err != nil {
		t.Fatal(err)
	}
	result, err := guestproductbootstrapartifactcompositionapplication.ExecuteGuestProductBootstrapArtifactComposition(
		guestproductbootstrapartifactcompositionapplication.GuestProductBootstrapArtifactCompositionExecution{GuestArtifactCompilationCommandPath: commandPath, InputRoot: inputRoot, OutputDirectory: outputDirectory},
	)
	if err != nil {
		t.Fatalf("compose C35 outputs: %v", err)
	}
	if result["guestProductBootstrapVolume"] != "storage/guest-product-bootstrap.raw" {
		t.Fatalf("result=%#v", result)
	}
	actualRoot, err := os.ReadFile(filepath.Join(outputDirectory, "storage", "guest-root.raw"))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(actualRoot, rootBytes) {
		t.Fatalf("Host changed declared root bytes: got %q want %q", actualRoot, rootBytes)
	}
	bootstrapInfo, err := os.Stat(filepath.Join(outputDirectory, "storage", "guest-product-bootstrap.raw"))
	if err != nil || bootstrapInfo.Size() < 1 {
		t.Fatalf("NoCloud bootstrap output is missing or empty: info=%v err=%v", bootstrapInfo, err)
	}
	assertExternalVitalServerDeliveryConfigurationIsDeclaredInNoCloudVolume(
		t,
		filepath.Join(outputDirectory, "storage", "guest-product-bootstrap.raw"),
		externalVitalServerDeliveryConfiguration,
	)
	assertGuestTelemetryCollectorIsDeclaredInNoCloudVolume(
		t,
		filepath.Join(outputDirectory, "storage", "guest-product-bootstrap.raw"),
		telemetryCollector,
		telemetryCollectorConfiguration,
	)
	outputs := regularOutputPaths(t, outputDirectory)
	wantOutputs := []string{"boot/Image", "boot/initrd.img", "storage/guest-product-bootstrap.raw", "storage/guest-root.raw"}
	if !equalStringSlices(outputs, wantOutputs) {
		t.Fatalf("outputs=%v want=%v", outputs, wantOutputs)
	}

	// amd64 providers boot the declared UEFI disk directly.  The same selected
	// C35 builder must therefore create the root and NoCloud volume without
	// fabricating macOS kernel/initial-ramdisk outputs.
	amdBootstrapConfiguration := strings.ReplaceAll(bootstrapConfiguration, "linux-arm64", "linux-amd64")
	amdBootstrapConfiguration = strings.Replace(amdBootstrapConfiguration, `"guestArchitecture":"arm64"`, `"guestArchitecture":"amd64"`, 1)
	writeArtifact("guest-runtime-linux-amd64", "inputs/services/guest-runtime", []byte("guest-runtime"))
	writeArtifact("guest-telemetry-collector-linux-amd64", "inputs/services/guest-telemetry-collector", telemetryCollector)
	writeArtifact("guest-node-services-linux-amd64", "inputs/services/guest-node-services.tar.gz", guestNodeServicesArchive(t))
	writeArtifact("guest-product-process-supervisor-linux-amd64", "inputs/services/guest-product-process-supervisor", []byte("process-supervisor"))
	writeArtifact("guest-product-release-manager-linux-amd64", "inputs/services/guest-product-release-manager", []byte("release-manager"))
	writeArtifact("linux-amd64-root-storage-base", "inputs/storage/guest-root.raw", rootBytes)
	writeArtifact("guest-product-bootstrap-configuration", "inputs/configuration/guest-product-bootstrap.json", []byte(amdBootstrapConfiguration))
	amdCommandBytes, err := json.Marshal(command)
	if err != nil {
		t.Fatal(err)
	}
	var amdCommand map[string]any
	if err := json.Unmarshal(amdCommandBytes, &amdCommand); err != nil {
		t.Fatal(err)
	}
	amdCommand["architecture"] = "amd64"
	delete(amdCommand, "boot")
	amdCommand["guestRuntimeArtifact"] = artifacts["guest-runtime-linux-amd64"]
	amdCommand["guestTelemetryCollectorArtifact"] = artifacts["guest-telemetry-collector-linux-amd64"]
	amdCommand["guestNodeServicesArtifact"] = artifacts["guest-node-services-linux-amd64"]
	amdCommand["guestProductProcessSupervisorArtifact"] = artifacts["guest-product-process-supervisor-linux-amd64"]
	amdCommand["guestProductReleaseManagerArtifact"] = artifacts["guest-product-release-manager-linux-amd64"]
	amdCommand["guestProductBootstrapConfigurationArtifact"] = artifacts["guest-product-bootstrap-configuration"]
	amdStorage := amdCommand["storageDevices"].([]any)
	amdStorage[0].(map[string]any)["baseImage"] = artifacts["linux-amd64-root-storage-base"]
	amdCommandPath := filepath.Join(root, "guest-artifact-compilation-command-amd64.json")
	amdCommandBytes, err = json.Marshal(amdCommand)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(amdCommandPath, amdCommandBytes, 0o600); err != nil {
		t.Fatal(err)
	}
	amdOutputDirectory := filepath.Join(root, "output-amd64")
	if err := os.MkdirAll(amdOutputDirectory, 0o700); err != nil {
		t.Fatal(err)
	}
	_, err = guestproductbootstrapartifactcompositionapplication.ExecuteGuestProductBootstrapArtifactComposition(
		guestproductbootstrapartifactcompositionapplication.GuestProductBootstrapArtifactCompositionExecution{GuestArtifactCompilationCommandPath: amdCommandPath, InputRoot: inputRoot, OutputDirectory: amdOutputDirectory},
	)
	if err != nil {
		t.Fatalf("compose amd64 C35 outputs: %v", err)
	}
	if amdOutputs := regularOutputPaths(t, amdOutputDirectory); !equalStringSlices(amdOutputs, []string{"storage/guest-product-bootstrap.raw", "storage/guest-root.raw"}) {
		t.Fatalf("amd64 outputs=%v", amdOutputs)
	}

	outsideServicesDirectory := filepath.Join(root, "outside-services")
	if err := os.Rename(filepath.Join(inputRoot, "inputs", "services"), outsideServicesDirectory); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outsideServicesDirectory, filepath.Join(inputRoot, "inputs", "services")); err != nil {
		t.Fatal(err)
	}
	symlinkOutputDirectory := filepath.Join(root, "output-with-symlinked-input")
	if err := os.MkdirAll(symlinkOutputDirectory, 0o700); err != nil {
		t.Fatal(err)
	}
	_, err = guestproductbootstrapartifactcompositionapplication.ExecuteGuestProductBootstrapArtifactComposition(
		guestproductbootstrapartifactcompositionapplication.GuestProductBootstrapArtifactCompositionExecution{GuestArtifactCompilationCommandPath: commandPath, InputRoot: inputRoot, OutputDirectory: symlinkOutputDirectory},
	)
	if err == nil || !strings.Contains(err.Error(), "input parent must be a directory non-symlink") {
		t.Fatalf("symlinked C35 input parent error=%v", err)
	}
	if paths := regularOutputPaths(t, symlinkOutputDirectory); len(paths) != 0 {
		t.Fatalf("symlinked C35 input published outputs=%v", paths)
	}
}

type testInputArtifact struct {
	ID                string `json:"id"`
	InputRelativePath string `json:"inputRelativePath"`
	SizeBytes         int64  `json:"sizeBytes"`
	SHA256            string `json:"sha256"`
}

func guestNodeServicesArchive(t *testing.T) []byte {
	t.Helper()
	var archive bytes.Buffer
	gzipWriter := gzip.NewWriter(&archive)
	tarWriter := tar.NewWriter(gzipWriter)
	for _, entry := range []struct{ path, contents string }{{"node/bin/node", "node"}, {"recorder-gateway/dist/cmd/recorder-gateway.js", "gateway"}, {"lab-recorder-runner/dist/cmd/lab-recorder-runner.js", "runner"}, {"lab-recorder-runner/lab-scenario-catalog.json", "{\"schemaVersion\":\"v1\",\"scenarios\":[]}"}} {
		if err := tarWriter.WriteHeader(&tar.Header{Name: entry.path, Mode: 0o755, Size: int64(len(entry.contents))}); err != nil {
			t.Fatal(err)
		}
		if _, err := tarWriter.Write([]byte(entry.contents)); err != nil {
			t.Fatal(err)
		}
	}
	if err := tarWriter.Close(); err != nil {
		t.Fatal(err)
	}
	if err := gzipWriter.Close(); err != nil {
		t.Fatal(err)
	}
	return archive.Bytes()
}

func regularOutputPaths(t *testing.T, root string) []string {
	t.Helper()
	var paths []string
	err := filepath.WalkDir(root, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() {
			return nil
		}
		relative, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		paths = append(paths, filepath.ToSlash(relative))
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	sort.Strings(paths)
	return paths
}

func equalStringSlices(left, right []string) bool {
	if len(left) != len(right) {
		return false
	}
	for index := range left {
		if left[index] != right[index] {
			return false
		}
	}
	return true
}

// assertExternalVitalServerDeliveryConfigurationIsDeclaredInNoCloudVolume
// keeps the C46 proof at the actual release-build boundary. C35 receipt
// provenance proves that C46 was a compiler input; this assertion opens the
// C40 RAW/ISO output and proves that the exact input byte and its explicit
// Guest installation instruction survived that compiler boundary together.
func assertExternalVitalServerDeliveryConfigurationIsDeclaredInNoCloudVolume(
	t *testing.T,
	rawBootstrapVolumePath string,
	expectedConfiguration []byte,
) {
	t.Helper()
	rawBootstrapVolume, err := os.ReadFile(rawBootstrapVolumePath)
	if err != nil {
		t.Fatal(err)
	}
	if len(rawBootstrapVolume) < 512 {
		t.Fatalf("C40 RAW bootstrap volume is smaller than one MBR sector")
	}
	partitionEntry := rawBootstrapVolume[446 : 446+16]
	partitionStart := int(binary.LittleEndian.Uint32(partitionEntry[8:12])) * 512
	partitionSize := int(binary.LittleEndian.Uint32(partitionEntry[12:16])) * 512
	if partitionStart < 512 || partitionSize < 1 || partitionStart+partitionSize > len(rawBootstrapVolume) {
		t.Fatalf("C40 RAW bootstrap partition bounds are invalid")
	}
	iso9660FilesystemPath := filepath.Join(t.TempDir(), "guest-product-bootstrap.iso9660")
	if err := os.WriteFile(
		iso9660FilesystemPath,
		rawBootstrapVolume[partitionStart:partitionStart+partitionSize],
		0o600,
	); err != nil {
		t.Fatal(err)
	}
	volume, err := diskfs.Open(iso9660FilesystemPath, diskfs.WithOpenMode(diskfs.ReadOnly))
	if err != nil {
		t.Fatal(err)
	}
	defer volume.Close()
	volumeFilesystem, err := volume.GetFilesystem(0)
	if err != nil {
		t.Fatal(err)
	}
	if volumeFilesystem.Type() != filesystem.TypeISO9660 {
		t.Fatalf("C40 bootstrap filesystem type=%v, want ISO9660", volumeFilesystem.Type())
	}
	isoFilesystem, ok := volumeFilesystem.(*iso9660.FileSystem)
	if !ok {
		t.Fatalf("C40 bootstrap filesystem adapter=%T, want ISO9660", volumeFilesystem)
	}
	actualConfiguration, err := isoFilesystem.ReadFile("payload/external-vitalserver-delivery-configuration")
	if err != nil {
		t.Fatalf("C40 bootstrap volume does not contain C46 payload: %v", err)
	}
	if !bytes.Equal(actualConfiguration, expectedConfiguration) {
		t.Fatalf("C40 bootstrap C46 payload differs from the C35 input")
	}
	manifestBytes, err := isoFilesystem.ReadFile("vitalserver-bootstrap-manifest.json")
	if err != nil {
		t.Fatalf("C40 bootstrap volume does not contain its composition plan: %v", err)
	}
	var manifest struct {
		FileInstallations []struct {
			SourceID        string `json:"sourceId"`
			DestinationPath string `json:"destinationPath"`
			FileMode        string `json:"fileMode"`
		} `json:"fileInstallations"`
	}
	if err := json.Unmarshal(manifestBytes, &manifest); err != nil {
		t.Fatalf("C40 bootstrap composition plan cannot be decoded: %v", err)
	}
	for _, installation := range manifest.FileInstallations {
		if installation.SourceID == "external-vitalserver-delivery-configuration" &&
			installation.DestinationPath == "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev/config/external-vitalserver-delivery-configuration.json" &&
			installation.FileMode == "0644" {
			return
		}
	}
	t.Fatalf("C40 bootstrap composition plan does not declare C46 Guest installation")
}

// assertGuestTelemetryCollectorIsDeclaredInNoCloudVolume proves the C35
// Collector bytes and C39 installation intent survive into C40 together. It
// deliberately reads the final Guest-visible ISO instead of inspecting the
// Host build staging directory.
func assertGuestTelemetryCollectorIsDeclaredInNoCloudVolume(
	t *testing.T,
	rawBootstrapVolumePath string,
	expectedCollector []byte,
	expectedConfiguration []byte,
) {
	t.Helper()
	rawBootstrapVolume, err := os.ReadFile(rawBootstrapVolumePath)
	if err != nil {
		t.Fatal(err)
	}
	if len(rawBootstrapVolume) < 512 {
		t.Fatalf("C40 RAW bootstrap volume is smaller than one MBR sector")
	}
	partitionEntry := rawBootstrapVolume[446 : 446+16]
	partitionStart := int(binary.LittleEndian.Uint32(partitionEntry[8:12])) * 512
	partitionSize := int(binary.LittleEndian.Uint32(partitionEntry[12:16])) * 512
	if partitionStart < 512 || partitionSize < 1 || partitionStart+partitionSize > len(rawBootstrapVolume) {
		t.Fatalf("C40 RAW bootstrap partition bounds are invalid")
	}
	iso9660FilesystemPath := filepath.Join(t.TempDir(), "guest-product-bootstrap-telemetry.iso9660")
	if err := os.WriteFile(
		iso9660FilesystemPath,
		rawBootstrapVolume[partitionStart:partitionStart+partitionSize],
		0o600,
	); err != nil {
		t.Fatal(err)
	}
	volume, err := diskfs.Open(iso9660FilesystemPath, diskfs.WithOpenMode(diskfs.ReadOnly))
	if err != nil {
		t.Fatal(err)
	}
	defer volume.Close()
	volumeFilesystem, err := volume.GetFilesystem(0)
	if err != nil {
		t.Fatal(err)
	}
	isoFilesystem, ok := volumeFilesystem.(*iso9660.FileSystem)
	if !ok {
		t.Fatalf("C40 bootstrap filesystem adapter=%T, want ISO9660", volumeFilesystem)
	}
	for path, expected := range map[string][]byte{
		"payload/guest-telemetry-collector-linux-arm64":   expectedCollector,
		"payload/guest-telemetry-collector-configuration": expectedConfiguration,
	} {
		actual, err := isoFilesystem.ReadFile(path)
		if err != nil {
			t.Fatalf("C40 bootstrap volume does not contain %s: %v", path, err)
		}
		if !bytes.Equal(actual, expected) {
			t.Fatalf("C40 bootstrap %s differs from its C35 input", path)
		}
	}
	manifestBytes, err := isoFilesystem.ReadFile("vitalserver-bootstrap-manifest.json")
	if err != nil {
		t.Fatalf("C40 bootstrap volume does not contain its composition plan: %v", err)
	}
	var manifest struct {
		GuestTelemetryStateDirectory *struct {
			DirectoryPath string `json:"directoryPath"`
			DirectoryMode string `json:"directoryMode"`
		} `json:"guestTelemetryStateDirectory"`
		FileInstallations []struct {
			SourceID        string `json:"sourceId"`
			DestinationPath string `json:"destinationPath"`
			FileMode        string `json:"fileMode"`
		} `json:"fileInstallations"`
	}
	if err := json.Unmarshal(manifestBytes, &manifest); err != nil {
		t.Fatalf("C40 bootstrap composition plan cannot be decoded: %v", err)
	}
	if manifest.GuestTelemetryStateDirectory == nil ||
		manifest.GuestTelemetryStateDirectory.DirectoryPath != "/var/lib/vitalserver/telemetry" ||
		manifest.GuestTelemetryStateDirectory.DirectoryMode != "0700" {
		t.Fatalf("C40 bootstrap composition plan has no declared telemetry state directory: %#v", manifest.GuestTelemetryStateDirectory)
	}
	expectedInstallations := map[string]struct {
		destinationPath string
		fileMode        string
	}{
		"guest-telemetry-collector-linux-arm64": {
			destinationPath: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev/bin/guest-telemetry-collector",
			fileMode:        "0755",
		},
		"guest-telemetry-collector-configuration": {
			destinationPath: "/opt/vitalserver/releases/vitalserver-guest-product-0.2.0-dev/config/guest-telemetry-collector.yaml",
			fileMode:        "0644",
		},
	}
	for _, installation := range manifest.FileInstallations {
		expected, found := expectedInstallations[installation.SourceID]
		if found && installation.DestinationPath == expected.destinationPath && installation.FileMode == expected.fileMode {
			delete(expectedInstallations, installation.SourceID)
		}
	}
	if len(expectedInstallations) != 0 {
		t.Fatalf("C40 bootstrap composition plan does not declare telemetry installations: %#v", expectedInstallations)
	}
}

func stringsOf(value string, count int) string { return strings.Repeat(value, count) }
