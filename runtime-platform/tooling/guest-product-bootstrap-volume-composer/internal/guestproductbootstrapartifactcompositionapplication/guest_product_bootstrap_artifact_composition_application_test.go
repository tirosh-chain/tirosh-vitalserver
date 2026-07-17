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
	writeArtifact("recorder-gateway-linux-arm64", "inputs/services/recorder-gateway.tar.gz", recorderGatewayArchive(t))
	writeArtifact("guest-product-process-supervisor-linux-arm64", "inputs/services/guest-product-process-supervisor", []byte("process-supervisor"))
	writeArtifact("guest-product-process-deployment-configuration", "inputs/configuration/guest-product-process-deployment.json", []byte(`{"schemaVersion":"v1","deploymentId":"guest-product","requiredProcessExitPolicy":"terminate-guest-product","guestRuntime":{"executablePath":"/opt/vitalserver/bin/guest-runtime","stateDatabasePath":"/var/lib/vitalserver/guest-runtime/guest-runtime.sqlite"},"recorderGateway":{"nodeExecutablePath":"/opt/vitalserver/node/bin/node","programPath":"/opt/vitalserver/recorder-gateway/dist/cmd/recorder-gateway.js","vitalServerTopologyDeploymentPath":"/etc/vitalserver/guest-product-vitalserver-topology-deployment.json","externalVitalServerDeliveryConfigurationPath":"/etc/vitalserver/external-vitalserver-delivery-configuration.json"}}`))
	writeArtifact("guest-product-service-manager-deployment-configuration", "inputs/configuration/guest-product-service-manager-deployment.json", []byte(`{"schemaVersion":"v1","serviceManagerKind":"systemd","serviceUnitName":"vitalserver-guest-product.service","supervisor":{"executablePath":"/opt/vitalserver/bin/guest-product-process-supervisor","deploymentConfigurationPath":"/etc/vitalserver/guest-product-process-deployment.json"},"restart":{"mode":"on-failure","delayMilliseconds":1000},"logging":{"standardOutput":"journal+console","standardError":"journal+console"},"install":{"wantedByTarget":"multi-user.target"}}`))
	writeArtifact("guest-product-bootstrap-configuration", "inputs/configuration/guest-product-bootstrap.json", []byte(`{"schemaVersion":"v1","bootstrapId":"vitalserver-guest-product-bootstrap","volumeLabel":"CIDATA","guestBootstrapVolumeFileSystem":"iso9660","instanceId":"guest-bootstrap","localHostName":"vitalserver-guest","guestRuntime":{"artifactId":"guest-runtime-linux-arm64","destinationPath":"/opt/vitalserver/bin/guest-runtime","fileMode":"0755"},"guestRuntimeStateDirectory":{"directoryPath":"/var/lib/vitalserver/guest-runtime","directoryMode":"0700"},"recorderGatewayBundle":{"artifactId":"recorder-gateway-linux-arm64","archiveFormat":"tar-gzip","entryModePolicy":"preserve-archive-mode","symbolicLinkPolicy":"allow-relative-links-to-declared-regular-files","destinationDirectory":"/opt/vitalserver","requiredArchivePaths":["node/bin/node","recorder-gateway/dist/cmd/recorder-gateway.js"]},"guestProductProcessSupervisor":{"artifactId":"guest-product-process-supervisor-linux-arm64","destinationPath":"/opt/vitalserver/bin/guest-product-process-supervisor","fileMode":"0755"},"guestProductProcessDeployment":{"artifactId":"guest-product-process-deployment-configuration","destinationPath":"/etc/vitalserver/guest-product-process-deployment.json","fileMode":"0644"},"guestProductVitalServerTopologyDeployment":{"artifactId":"guest-product-vitalserver-topology-deployment","destinationPath":"/etc/vitalserver/guest-product-vitalserver-topology-deployment.json","fileMode":"0644"},"externalVitalServerDeliveryConfiguration":{"artifactId":"external-vitalserver-delivery-configuration","destinationPath":"/etc/vitalserver/external-vitalserver-delivery-configuration.json","fileMode":"0644"},"guestProductServiceManagerDeployment":{"artifactId":"guest-product-service-manager-deployment-configuration","configurationDestinationPath":"/etc/vitalserver/guest-product-service-manager-deployment.json","unitDestinationPath":"/etc/systemd/system/vitalserver-guest-product.service","enabledUnitLinkPath":"/etc/systemd/system/multi-user.target.wants/vitalserver-guest-product.service","enabledUnitLinkTargetPath":"/etc/systemd/system/vitalserver-guest-product.service"}}`))
	writeArtifact("guest-product-vitalserver-topology-deployment", "inputs/configuration/guest-product-vitalserver-topology-deployment.json", []byte(`{"schemaVersion":"v1","topologyDeploymentId":"external-vitalserver-primary-topology","topologyKind":"external-vitalserver","vitalServerDeliveryProvider":{"kind":"external-vitalserver","id":"external-vitalserver-primary","capabilityRevision":1},"publicBrowserExposure":"not-exposed","externalVitalServerDeploymentConfiguration":{"externalUpstreamIntegrationReference":{"resourceType":"external-upstream-integration","resourceId":"external-vitalserver-primary"},"externalVitalServerDeliveryConfigurationReference":{"resourceType":"external-vitalserver-delivery-configuration","resourceId":"external-vitalserver-primary-delivery"}}}`))
	externalVitalServerDeliveryConfiguration := []byte(`{"schemaVersion":"v1","configurationId":"external-vitalserver-primary-delivery","externalUpstreamIntegrationReference":{"resourceType":"external-upstream-integration","resourceId":"external-vitalserver-primary"},"vitalServerDeliveryProvider":{"kind":"external-vitalserver","id":"external-vitalserver-primary","capabilityRevision":1},"vitalServerPacketDeliveryEndpoint":{"scheme":"https","host":"vitalserver.external.example","port":443},"vitalServerDeliveryAcknowledgementTimeoutMilliseconds":1000}`)
	writeArtifact("external-vitalserver-delivery-configuration", "inputs/configuration/external-vitalserver-delivery-configuration.json", externalVitalServerDeliveryConfiguration)
	rootBytes := []byte("immutable-declared-root-storage")
	writeArtifact("linux-arm64-root-storage-base", "inputs/storage/guest-root.raw", rootBytes)

	command := map[string]any{
		"schemaVersion": "v1", "compilationId": "guest-artifact-composition-test", "artifactSetId": "guest-artifact-set", "architecture": "arm64",
		"buildEnvironment":     map[string]any{"id": "guest-product-bootstrap-artifact-composer", "builderExecutableSizeBytes": 1, "builderExecutableSHA256": stringsOf("a", 64)},
		"boot":                 map[string]any{"kernel": map[string]any{"source": artifacts["linux-arm64-kernel"], "outputRelativePath": "boot/Image"}, "initialRamdisk": map[string]any{"source": artifacts["linux-arm64-initrd"], "outputRelativePath": "boot/initrd.img"}},
		"guestRuntimeArtifact": artifacts["guest-runtime-linux-arm64"], "recorderGatewayArtifact": artifacts["recorder-gateway-linux-arm64"],
		"guestProductProcessSupervisorArtifact": artifacts["guest-product-process-supervisor-linux-arm64"], "guestProductProcessDeploymentConfigurationArtifact": artifacts["guest-product-process-deployment-configuration"], "guestProductServiceManagerDeploymentConfigurationArtifact": artifacts["guest-product-service-manager-deployment-configuration"], "guestProductBootstrapConfigurationArtifact": artifacts["guest-product-bootstrap-configuration"], "guestProductVitalServerTopologyDeploymentArtifact": artifacts["guest-product-vitalserver-topology-deployment"], "externalVitalServerDeliveryConfigurationArtifact": artifacts["external-vitalserver-delivery-configuration"],
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
	outputs := regularOutputPaths(t, outputDirectory)
	wantOutputs := []string{"boot/Image", "boot/initrd.img", "storage/guest-product-bootstrap.raw", "storage/guest-root.raw"}
	if !equalStringSlices(outputs, wantOutputs) {
		t.Fatalf("outputs=%v want=%v", outputs, wantOutputs)
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

func recorderGatewayArchive(t *testing.T) []byte {
	t.Helper()
	var archive bytes.Buffer
	gzipWriter := gzip.NewWriter(&archive)
	tarWriter := tar.NewWriter(gzipWriter)
	for _, entry := range []struct{ path, contents string }{{"node/bin/node", "node"}, {"recorder-gateway/dist/cmd/recorder-gateway.js", "gateway"}} {
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
			installation.DestinationPath == "/etc/vitalserver/external-vitalserver-delivery-configuration.json" &&
			installation.FileMode == "0644" {
			return
		}
	}
	t.Fatalf("C40 bootstrap composition plan does not declare C46 Guest installation")
}

func stringsOf(value string, count int) string { return strings.Repeat(value, count) }
