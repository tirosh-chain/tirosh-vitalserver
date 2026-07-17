package guestproductbootstrapvolumeapplication_test

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
	"strings"
	"testing"

	diskfs "github.com/diskfs/go-diskfs"
	"github.com/diskfs/go-diskfs/filesystem"
	"github.com/diskfs/go-diskfs/filesystem/iso9660"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-bootstrap-volume-composer/internal/guestproductbootstrapvolumeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-bootstrap-volume-composer/internal/guestproductbootstrapvolumeplan"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-bootstrap-volume-composer/internal/nocloudguestproductbootstrapvolumeadapter"
)

func TestGuestProductBootstrapVolumeCompositionProducesVerifiedNoCloudVolume(t *testing.T) {
	root := t.TempDir()
	sourceRoot := filepath.Join(root, "source-root")
	if err := os.Mkdir(sourceRoot, 0o755); err != nil {
		t.Fatal(err)
	}
	plan := writeDeclaredBootstrapSourcesAndPlan(t, sourceRoot)
	planPath := filepath.Join(root, "guest-product-bootstrap-volume-composition-plan.json")
	planBytes, err := json.Marshal(plan)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(planPath, planBytes, 0o600); err != nil {
		t.Fatal(err)
	}
	outputPath := filepath.Join(root, "vitalserver-bootstrap.raw")
	bootstrapID, err := guestproductbootstrapvolumeapplication.ExecuteGuestProductBootstrapVolumeComposition(
		guestproductbootstrapvolumeapplication.GuestProductBootstrapVolumeCompositionExecution{
			CompositionPlanPath: planPath,
			SourceRoot:          sourceRoot,
			OutputVolumePath:    outputPath,
		},
		nocloudguestproductbootstrapvolumeadapter.NewNoCloudGuestProductBootstrapVolumeAdapter(),
	)
	if err != nil {
		t.Fatalf("compose C40 NoCloud volume: %v", err)
	}
	if bootstrapID != plan.BootstrapID {
		t.Fatalf("bootstrap id=%q, want %q", bootstrapID, plan.BootstrapID)
	}
	assertNoCloudVolumeContents(t, outputPath, plan)
}

func TestGuestProductBootstrapVolumeCompositionRejectsTamperedSourceWithoutOutput(t *testing.T) {
	root := t.TempDir()
	sourceRoot := filepath.Join(root, "source-root")
	if err := os.Mkdir(sourceRoot, 0o755); err != nil {
		t.Fatal(err)
	}
	plan := writeDeclaredBootstrapSourcesAndPlan(t, sourceRoot)
	if err := os.WriteFile(filepath.Join(sourceRoot, "sources", "guest-runtime-linux-arm64"), []byte("tampered-xxxx"), 0o600); err != nil {
		t.Fatal(err)
	}
	planPath := filepath.Join(root, "guest-product-bootstrap-volume-composition-plan.json")
	planBytes, err := json.Marshal(plan)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(planPath, planBytes, 0o600); err != nil {
		t.Fatal(err)
	}
	outputPath := filepath.Join(root, "vitalserver-bootstrap.raw")
	_, err = guestproductbootstrapvolumeapplication.ExecuteGuestProductBootstrapVolumeComposition(
		guestproductbootstrapvolumeapplication.GuestProductBootstrapVolumeCompositionExecution{CompositionPlanPath: planPath, SourceRoot: sourceRoot, OutputVolumePath: outputPath},
		nocloudguestproductbootstrapvolumeadapter.NewNoCloudGuestProductBootstrapVolumeAdapter(),
	)
	if err == nil || !strings.Contains(err.Error(), "sha256 differs") {
		t.Fatalf("expected explicit source identity failure, got %v", err)
	}
	if _, err := os.Lstat(outputPath); !os.IsNotExist(err) {
		t.Fatalf("failed composition published output: %v", err)
	}
}

func writeDeclaredBootstrapSourcesAndPlan(t *testing.T, sourceRoot string) guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan {
	t.Helper()
	if err := os.Mkdir(filepath.Join(sourceRoot, "sources"), 0o755); err != nil {
		t.Fatal(err)
	}
	contentsByID := map[string][]byte{
		"guest-runtime-linux-arm64":                              []byte("guest-runtime"),
		"guest-product-process-supervisor-linux-arm64":           []byte("guest-product-process-supervisor"),
		"guest-product-process-deployment-configuration":         []byte(`{"schemaVersion":"v1"}`),
		"guest-product-vitalserver-topology-deployment":          []byte(`{"schemaVersion":"v1"}`),
		"guest-product-service-manager-deployment-configuration": []byte(`{"schemaVersion":"v1"}`),
		"guest-product-systemd-unit":                             []byte("[Service]\nExecStart=/opt/vitalserver/bin/guest-product-process-supervisor\n"),
		"recorder-gateway-linux-arm64":                           testRecorderGatewayArchive(t),
	}
	sources := make([]guestproductbootstrapvolumeplan.DeclaredBootstrapSource, 0, len(contentsByID))
	for identifier, contents := range contentsByID {
		path := filepath.Join(sourceRoot, "sources", identifier)
		if err := os.WriteFile(path, contents, 0o600); err != nil {
			t.Fatal(err)
		}
		digest := sha256.Sum256(contents)
		sources = append(sources, guestproductbootstrapvolumeplan.DeclaredBootstrapSource{
			ID: identifier, SourceRelativePath: "sources/" + identifier, SizeBytes: int64(len(contents)), SHA256: hex.EncodeToString(digest[:]),
		})
	}
	return guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan{
		SchemaVersion: "v1", BootstrapID: "vitalserver-guest-bootstrap", VolumeLabel: "CIDATA", StorageImageFormat: "raw", GuestVolumeFileSystem: "iso9660", InstanceID: "vitalserver-guest-bootstrap-instance", LocalHostName: "vitalserver-guest", ServiceUnitName: "vitalserver-guest-product.service",
		GuestRuntimeStateDirectory: guestproductbootstrapvolumeplan.DeclaredGuestDirectory{DirectoryPath: "/var/lib/vitalserver/guest-runtime", DirectoryMode: "0700"},
		Sources:                    sources,
		FileInstallations: []guestproductbootstrapvolumeplan.DeclaredGuestFileInstallation{
			{SourceID: "guest-runtime-linux-arm64", DestinationPath: "/opt/vitalserver/bin/guest-runtime", FileMode: "0755"},
			{SourceID: "guest-product-process-supervisor-linux-arm64", DestinationPath: "/opt/vitalserver/bin/guest-product-process-supervisor", FileMode: "0755"},
			{SourceID: "guest-product-process-deployment-configuration", DestinationPath: "/etc/vitalserver/guest-product-process-deployment.json", FileMode: "0644"},
			{SourceID: "guest-product-vitalserver-topology-deployment", DestinationPath: "/etc/vitalserver/guest-product-vitalserver-topology-deployment.json", FileMode: "0644"},
			{SourceID: "guest-product-service-manager-deployment-configuration", DestinationPath: "/etc/vitalserver/guest-product-service-manager-deployment.json", FileMode: "0644"},
			{SourceID: "guest-product-systemd-unit", DestinationPath: "/etc/systemd/system/vitalserver-guest-product.service", FileMode: "0644"},
		},
		ArchiveInstallations: []guestproductbootstrapvolumeplan.DeclaredGuestArchiveInstallation{{
			SourceID: "recorder-gateway-linux-arm64", ArchiveFormat: "tar-gzip", EntryModePolicy: "preserve-archive-mode", SymbolicLinkPolicy: guestproductbootstrapvolumeplan.AllowRelativeLinksToDeclaredRegularFilesPolicy, DestinationDirectory: "/opt/vitalserver", RequiredArchivePaths: []string{"node/bin/node", "recorder-gateway/dist/cmd/recorder-gateway.js"},
		}},
		SymbolicLinks: []guestproductbootstrapvolumeplan.DeclaredGuestSymbolicLink{{LinkPath: "/etc/systemd/system/multi-user.target.wants/vitalserver-guest-product.service", TargetPath: "/etc/systemd/system/vitalserver-guest-product.service"}},
	}
}

func testRecorderGatewayArchive(t *testing.T) []byte {
	t.Helper()
	var compressed bytes.Buffer
	gzipWriter := gzip.NewWriter(&compressed)
	tarWriter := tar.NewWriter(gzipWriter)
	for _, entry := range []struct{ name, contents, symbolicLinkTarget string }{
		{"node/", "", ""}, {"node/bin/", "", ""}, {"node/bin/node", "node", ""},
		{"recorder-gateway/", "", ""}, {"recorder-gateway/dist/", "", ""}, {"recorder-gateway/dist/cmd/", "", ""}, {"recorder-gateway/dist/cmd/recorder-gateway.js", "gateway", ""},
		{"recorder-gateway/node_modules/", "", ""}, {"recorder-gateway/node_modules/.bin/", "", ""}, {"recorder-gateway/node_modules/typescript/", "", ""}, {"recorder-gateway/node_modules/typescript/bin/", "", ""},
		{"recorder-gateway/node_modules/typescript/bin/tsserver", "typescript-server", ""}, {"recorder-gateway/node_modules/typescript/bin/tsc", "typescript-compiler", ""},
		{"recorder-gateway/node_modules/.bin/tsserver", "", "../typescript/bin/tsserver"}, {"recorder-gateway/node_modules/.bin/tsc", "", "../typescript/bin/tsc"},
	} {
		header := &tar.Header{Name: entry.name, Mode: 0o755}
		if entry.symbolicLinkTarget != "" {
			header.Typeflag = tar.TypeSymlink
			header.Linkname = entry.symbolicLinkTarget
		} else if entry.contents == "" {
			header.Typeflag = tar.TypeDir
		} else {
			header.Typeflag, header.Size = tar.TypeReg, int64(len(entry.contents))
		}
		if err := tarWriter.WriteHeader(header); err != nil {
			t.Fatal(err)
		}
		if entry.contents != "" {
			if _, err := tarWriter.Write([]byte(entry.contents)); err != nil {
				t.Fatal(err)
			}
		}
	}
	if err := tarWriter.Close(); err != nil {
		t.Fatal(err)
	}
	if err := gzipWriter.Close(); err != nil {
		t.Fatal(err)
	}
	return compressed.Bytes()
}

func assertNoCloudVolumeContents(t *testing.T, volumePath string, plan guestproductbootstrapvolumeplan.GuestProductBootstrapVolumeCompositionPlan) {
	t.Helper()
	rawStorageImage, err := os.ReadFile(volumePath)
	if err != nil {
		t.Fatal(err)
	}
	if len(rawStorageImage) < 512 || rawStorageImage[510] != 0x55 || rawStorageImage[511] != 0xaa {
		t.Fatalf("bootstrap artifact is not a RAW MBR storage image")
	}
	partitionEntry := rawStorageImage[446 : 446+16]
	if partitionEntry[4] != 0xcd {
		t.Fatalf("bootstrap MBR partition type=%#x, want ISO9660 %#x", partitionEntry[4], byte(0xcd))
	}
	partitionStart := int(binary.LittleEndian.Uint32(partitionEntry[8:12])) * 512
	partitionSize := int(binary.LittleEndian.Uint32(partitionEntry[12:16])) * 512
	if partitionStart < 512 || partitionSize < 1 || partitionStart+partitionSize > len(rawStorageImage) {
		t.Fatalf("bootstrap MBR partition bounds are invalid")
	}
	iso9660FilesystemPath := filepath.Join(filepath.Dir(volumePath), "extracted-bootstrap.iso9660")
	if err := os.WriteFile(iso9660FilesystemPath, rawStorageImage[partitionStart:partitionStart+partitionSize], 0o600); err != nil {
		t.Fatal(err)
	}
	volume, err := diskfs.Open(iso9660FilesystemPath, diskfs.WithOpenMode(diskfs.ReadOnly))
	if err != nil {
		t.Fatal(err)
	}
	defer volume.Close()
	filesystemValue, err := volume.GetFilesystem(0)
	if err != nil {
		t.Fatal(err)
	}
	if filesystemValue.Type() != filesystem.TypeISO9660 {
		t.Fatalf("filesystem type=%v, want ISO9660", filesystemValue.Type())
	}
	isoFilesystem, ok := filesystemValue.(*iso9660.FileSystem)
	if !ok {
		t.Fatalf("filesystem adapter=%T, want ISO9660", filesystemValue)
	}
	metaData, err := isoFilesystem.ReadFile("meta-data")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(metaData), "instance-id: "+plan.InstanceID) {
		t.Fatalf("meta-data does not name declared instance: %s", metaData)
	}
	userData, err := isoFilesystem.ReadFile("user-data")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(userData), "\nruncmd:\n") || !strings.Contains(string(userData), "sha256sum -c -") {
		t.Fatalf("user-data lacks Guest-owned bootstrap contract: %s", userData)
	}
	assertCloudInitWriteFileBlockScalarIsIndented(t, string(userData))
	if !strings.Contains(string(userData), "systemctl start "+plan.ServiceUnitName) {
		t.Fatalf("user-data does not activate the declared service unit %q: %s", plan.ServiceUnitName, userData)
	}
	for _, source := range plan.Sources {
		payload, err := isoFilesystem.ReadFile("payload/" + source.ID)
		if err != nil {
			t.Fatalf("read payload %s: %v", source.ID, err)
		}
		if int64(len(payload)) != source.SizeBytes {
			t.Fatalf("payload %s size=%d, want %d", source.ID, len(payload), source.SizeBytes)
		}
		digest := sha256.Sum256(payload)
		if hex.EncodeToString(digest[:]) != source.SHA256 {
			t.Fatalf("payload %s identity differs", source.ID)
		}
	}
}

// assertCloudInitWriteFileBlockScalarIsIndented protects the exact boundary
// that cloud-init consumes. A bootstrap volume with an invalid YAML block
// scalar can still have correct source hashes and ISO contents, while the
// Guest never receives any Product payload.
func assertCloudInitWriteFileBlockScalarIsIndented(t *testing.T, userData string) {
	t.Helper()
	lines := strings.Split(userData, "\n")
	contentLine := -1
	for index, line := range lines {
		if line == "    content: |" {
			contentLine = index
			break
		}
	}
	if contentLine == -1 {
		t.Fatalf("cloud-init user-data has no write_files content block: %s", userData)
	}
	for index := contentLine + 1; index < len(lines); index++ {
		if lines[index] == "runcmd:" {
			return
		}
		if lines[index] == "" {
			continue
		}
		if !strings.HasPrefix(lines[index], "      ") {
			t.Fatalf("cloud-init write_files content line %d is not nested below content: %q", index+1, lines[index])
		}
	}
	t.Fatalf("cloud-init user-data has no runcmd after write_files content: %s", userData)
}
