package hostplatformreleasearchivecomposition

import (
	"archive/tar"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"testing"
)

func TestComposeHostPlatformReleaseArchiveCreatesRigidC68Layout(t *testing.T) {
	root := t.TempDir()
	release := filepath.Join(root, "release")
	if err := os.MkdirAll(filepath.Join(release, "bin"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(release, "bin", "host-agent"), []byte("host-agent"), 0o755); err != nil {
		t.Fatal(err)
	}
	services := map[string]string{}
	for _, role := range []string{"host-agent", "host-edge-proxy", "host-update-handoff-supervisor"} {
		path := filepath.Join(root, role+".plist")
		if err := os.WriteFile(path, []byte(role), 0o600); err != nil {
			t.Fatal(err)
		}
		services[role] = path
	}
	bootstrap := filepath.Join(root, "runtime-console-bootstrap.json")
	if err := os.WriteFile(bootstrap, []byte(`{"schemaVersion":"v1"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	writeTestManifest(t, release, services, bootstrap)
	composition := filepath.Join(root, "composition.json")
	writeComposition(t, composition, release, services, bootstrap)
	firstPath := filepath.Join(root, "release.tar.gz")
	first, err := ComposeHostPlatformReleaseArchive(ComposeHostPlatformReleaseArchiveRequest{CompositionPath: composition, OutputArchivePath: firstPath})
	if err != nil {
		t.Fatalf("compose C68 archive: %v", err)
	}
	if first.MediaType != hostPlatformReleaseArchiveMediaType || first.SizeBytes < 1 || len(first.SHA256) != 64 {
		t.Fatalf("archive=%+v", first)
	}
	entries := readArchive(t, firstPath)
	for _, required := range []string{"release/installation-manifest.json", "release/bin/host-agent", "service-definitions/host-agent.plist", "service-definitions/host-edge-proxy.plist", "service-definitions/host-update-handoff-supervisor.plist", "operator-interface/runtime-console-bootstrap.json"} {
		if !entries[required] {
			t.Fatalf("C68 archive omits %s: %v", required, entries)
		}
	}
	secondPath := filepath.Join(root, "release-again.tar.gz")
	second, err := ComposeHostPlatformReleaseArchive(ComposeHostPlatformReleaseArchiveRequest{CompositionPath: composition, OutputArchivePath: secondPath})
	if err != nil {
		t.Fatal(err)
	}
	if first.SHA256 != second.SHA256 || first.SizeBytes != second.SizeBytes {
		t.Fatalf("C68 archive is non-deterministic first=%+v second=%+v", first, second)
	}
}

func TestComposeHostPlatformReleaseArchiveRejectsUndeclaredReleaseFile(t *testing.T) {
	root := t.TempDir()
	release := filepath.Join(root, "release")
	if err := os.MkdirAll(filepath.Join(release, "bin"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(release, "bin", "host-agent"), []byte("host-agent"), 0o755); err != nil {
		t.Fatal(err)
	}
	services := map[string]string{}
	for _, role := range []string{"host-agent", "host-edge-proxy", "host-update-handoff-supervisor"} {
		path := filepath.Join(root, role+".plist")
		if err := os.WriteFile(path, []byte(role), 0o600); err != nil {
			t.Fatal(err)
		}
		services[role] = path
	}
	bootstrap := filepath.Join(root, "runtime-console-bootstrap.json")
	if err := os.WriteFile(bootstrap, []byte(`{"schemaVersion":"v1"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	writeTestManifest(t, release, services, bootstrap)
	if err := os.WriteFile(filepath.Join(release, "untracked"), []byte("unsafe"), 0o600); err != nil {
		t.Fatal(err)
	}
	composition := filepath.Join(root, "composition.json")
	writeComposition(t, composition, release, services, bootstrap)
	if _, err := ComposeHostPlatformReleaseArchive(ComposeHostPlatformReleaseArchiveRequest{CompositionPath: composition, OutputArchivePath: filepath.Join(root, "release.tar.gz")}); err == nil {
		t.Fatal("expected undeclared release file rejection")
	}
}

func TestServiceDefinitionArchiveNameFollowsDeclaredPlatform(t *testing.T) {
	for _, test := range []struct {
		platform string
		want     string
	}{
		{platform: "macos", want: "host-agent.plist"},
		{platform: "linux", want: "host-agent.service"},
		{platform: "windows", want: "host-agent.json"},
	} {
		got, err := serviceDefinitionArchiveName(test.platform, "host-agent")
		if err != nil || got != test.want {
			t.Fatalf("platform %s: got=%q err=%v want=%q", test.platform, got, err, test.want)
		}
	}
	if _, err := serviceDefinitionArchiveName("unsupported", "host-agent"); err == nil {
		t.Fatal("expected unsupported platform to be rejected")
	}
}

func writeTestManifest(t *testing.T, release string, sources map[string]string, bootstrap string) {
	t.Helper()
	manifest := map[string]any{
		"schemaVersion": "v1", "installationId": "installation-001", "platform": "macos",
		"release":          map[string]any{"id": "runtime-platform-030", "productVersion": "0.3.0", "runtimeVersion": "0.3.0"},
		"package":          map[string]any{"identifier": "com.tirosh.vitalserver.runtime-platform", "productVersion": "0.3.0"},
		"immutablePayload": map[string]any{"releaseCatalogPath": "/Library/Application Support/VitalServerRuntimePlatform/releases", "releaseRootPath": "/Library/Application Support/VitalServerRuntimePlatform/releases/runtime-platform-030", "manifestPath": "/Library/Application Support/VitalServerRuntimePlatform/releases/runtime-platform-030/installation-manifest.json", "entries": []any{map[string]any{"relativePath": "bin/host-agent", "sha256": digestFile(t, filepath.Join(release, "bin", "host-agent")), "executable": true}}},
		"activation":       map[string]any{"currentReleaseLinkPath": "/Library/Application Support/VitalServerRuntimePlatform/current", "referenceKind": "symbolic-link", "expectedReleaseRootPath": "/Library/Application Support/VitalServerRuntimePlatform/releases/runtime-platform-030"},
		"operatorInterface": map[string]any{
			"bootstrapConfigurationPath":              "/Library/Application Support/VitalServerRuntimePlatform/control/runtime-console-bootstrap.json",
			"bootstrapConfigurationSha256":            digestFile(t, bootstrap),
			"applicationBundlePath":                   "/Applications/VitalServer Runtime Platform.app",
			"applicationBundleTreeSha256":             "6666666666666666666666666666666666666666666666666666666666666666",
			"applicationBundleEntrypointRelativePath": "Contents/MacOS/VitalServer Runtime Platform",
		},
		"requiredServices": []any{
			map[string]any{"role": "host-agent", "manager": "launchd", "name": "com.tirosh.vitalserver.host-agent", "definitionPath": "/Library/LaunchDaemons/com.tirosh.vitalserver.host-agent.plist", "definitionSha256": digestFile(t, sources["host-agent"])},
			map[string]any{"role": "host-edge-proxy", "manager": "launchd", "name": "com.tirosh.vitalserver.host-edge-proxy", "definitionPath": "/Library/LaunchDaemons/com.tirosh.vitalserver.host-edge-proxy.plist", "definitionSha256": digestFile(t, sources["host-edge-proxy"])},
			map[string]any{"role": "host-update-handoff-supervisor", "manager": "launchd", "name": "com.tirosh.vitalserver.host-update-handoff-supervisor", "definitionPath": "/Library/LaunchDaemons/com.tirosh.vitalserver.host-update-handoff-supervisor.plist", "definitionSha256": digestFile(t, sources["host-update-handoff-supervisor"])},
		},
		"mutableStores": []any{map[string]any{"id": "installation-manager", "path": "/Library/Application Support/VitalServerRuntimePlatform/data/installation-manager", "kind": "directory", "owner": "host-installation-manager", "retention": "preserve-by-default"}},
	}
	bytes, err := json.Marshal(manifest)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(release, "installation-manifest.json"), append(bytes, '\n'), 0o600); err != nil {
		t.Fatal(err)
	}
}

func TestComposeHostPlatformReleaseArchiveRejectsIncompleteMacOSApplicationBundleContract(t *testing.T) {
	root := t.TempDir()
	release := filepath.Join(root, "release")
	if err := os.MkdirAll(filepath.Join(release, "bin"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(release, "bin", "host-agent"), []byte("host-agent"), 0o755); err != nil {
		t.Fatal(err)
	}
	services := map[string]string{}
	for _, role := range []string{"host-agent", "host-edge-proxy", "host-update-handoff-supervisor"} {
		path := filepath.Join(root, role+".plist")
		if err := os.WriteFile(path, []byte(role), 0o600); err != nil {
			t.Fatal(err)
		}
		services[role] = path
	}
	bootstrap := filepath.Join(root, "runtime-console-bootstrap.json")
	if err := os.WriteFile(bootstrap, []byte(`{"schemaVersion":"v1"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	writeTestManifest(t, release, services, bootstrap)
	manifestPath := filepath.Join(release, "installation-manifest.json")
	var manifest map[string]any
	contents, err := os.ReadFile(manifestPath)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(contents, &manifest); err != nil {
		t.Fatal(err)
	}
	delete(manifest["operatorInterface"].(map[string]any), "applicationBundleTreeSha256")
	contents, err = json.Marshal(manifest)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(manifestPath, append(contents, '\n'), 0o600); err != nil {
		t.Fatal(err)
	}
	composition := filepath.Join(root, "composition.json")
	writeComposition(t, composition, release, services, bootstrap)

	if _, err := ComposeHostPlatformReleaseArchive(ComposeHostPlatformReleaseArchiveRequest{
		CompositionPath:   composition,
		OutputArchivePath: filepath.Join(root, "release.tar.gz"),
	}); err == nil {
		t.Fatal("expected incomplete macOS application bundle declaration rejection")
	}
}
func writeComposition(t *testing.T, path, release string, sources map[string]string, bootstrap string) {
	t.Helper()
	value := HostPlatformReleaseArchiveComposition{SchemaVersion: "v1", ReleaseSourceDirectory: release, OperatorInterfaceBootstrapSourcePath: bootstrap}
	for _, role := range []string{"host-agent", "host-edge-proxy", "host-update-handoff-supervisor"} {
		value.ServiceDefinitionSources = append(value.ServiceDefinitionSources, HostPlatformServiceSource{Role: role, SourcePath: sources[role]})
	}
	bytes, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, append(bytes, '\n'), 0o600); err != nil {
		t.Fatal(err)
	}
}
func digestFile(t *testing.T, path string) string {
	t.Helper()
	contents, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	digest := sha256.Sum256(contents)
	return hex.EncodeToString(digest[:])
}
func readArchive(t *testing.T, path string) map[string]bool {
	t.Helper()
	file, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	gzipReader, err := gzip.NewReader(file)
	if err != nil {
		t.Fatal(err)
	}
	defer gzipReader.Close()
	reader := tar.NewReader(gzipReader)
	entries := map[string]bool{}
	for {
		header, err := reader.Next()
		if err == io.EOF {
			return entries
		}
		if err != nil {
			t.Fatal(err)
		}
		entries[header.Name] = true
	}
}
