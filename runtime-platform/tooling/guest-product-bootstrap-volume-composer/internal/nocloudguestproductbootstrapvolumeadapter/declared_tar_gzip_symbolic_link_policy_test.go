package nocloudguestproductbootstrapvolumeadapter

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"strings"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-bootstrap-volume-composer/internal/guestproductbootstrapvolumeplan"
)

func TestValidateDeclaredTarGzipContentsAcceptsRelativeLinkToDeclaredRegularFile(t *testing.T) {
	archive := declaredTarGzipReader(t, []declaredTarGzipTestEntry{
		{name: "recorder-gateway/", typeFlag: tar.TypeDir},
		{name: "recorder-gateway/node_modules/", typeFlag: tar.TypeDir},
		{name: "recorder-gateway/node_modules/.bin/", typeFlag: tar.TypeDir},
		{name: "recorder-gateway/node_modules/typescript/", typeFlag: tar.TypeDir},
		{name: "recorder-gateway/node_modules/typescript/bin/", typeFlag: tar.TypeDir},
		{name: "recorder-gateway/node_modules/typescript/bin/tsserver", contents: "typescript server"},
		{name: "recorder-gateway/node_modules/.bin/tsserver", typeFlag: tar.TypeSymlink, symbolicLinkTarget: "../typescript/bin/tsserver"},
		{name: "node/bin/node", contents: "node"},
		{name: "recorder-gateway/dist/cmd/recorder-gateway.js", contents: "gateway"},
	})

	err := validateDeclaredTarGzipContents(
		archive,
		[]string{"node/bin/node", "recorder-gateway/dist/cmd/recorder-gateway.js"},
		guestproductbootstrapvolumeplan.AllowRelativeLinksToDeclaredRegularFilesPolicy,
	)
	if err != nil {
		t.Fatalf("expected declared relative regular-file link to be accepted: %v", err)
	}
}

func TestValidateDeclaredTarGzipContentsRejectsSymbolicLinkOutsideArchiveRoot(t *testing.T) {
	archive := declaredTarGzipReader(t, []declaredTarGzipTestEntry{
		{name: "recorder-gateway/node_modules/.bin/escape", typeFlag: tar.TypeSymlink, symbolicLinkTarget: "../../../../outside"},
	})

	err := validateDeclaredTarGzipContents(archive, nil, guestproductbootstrapvolumeplan.AllowRelativeLinksToDeclaredRegularFilesPolicy)
	if err == nil || !strings.Contains(err.Error(), "escapes archive root") {
		t.Fatalf("expected an archive-root escape rejection, got %v", err)
	}
}

func TestValidateDeclaredTarGzipContentsRejectsSymbolicLinkToDeclaredDirectory(t *testing.T) {
	archive := declaredTarGzipReader(t, []declaredTarGzipTestEntry{
		{name: "recorder-gateway/node_modules/typescript/", typeFlag: tar.TypeDir},
		{name: "recorder-gateway/node_modules/.bin/tsserver", typeFlag: tar.TypeSymlink, symbolicLinkTarget: "../typescript"},
	})

	err := validateDeclaredTarGzipContents(archive, nil, guestproductbootstrapvolumeplan.AllowRelativeLinksToDeclaredRegularFilesPolicy)
	if err == nil || !strings.Contains(err.Error(), "does not name a declared regular file") {
		t.Fatalf("expected a directory-link rejection, got %v", err)
	}
}

func TestValidateDeclaredTarGzipContentsRejectsUnknownSymbolicLinkPolicy(t *testing.T) {
	archive := declaredTarGzipReader(t, nil)

	err := validateDeclaredTarGzipContents(archive, nil, "allow-all-symbolic-links")
	if err == nil || !strings.Contains(err.Error(), "symbolic link policy") {
		t.Fatalf("expected an unknown symbolic-link policy rejection, got %v", err)
	}
}

type declaredTarGzipTestEntry struct {
	name               string
	typeFlag           byte
	contents           string
	symbolicLinkTarget string
}

func declaredTarGzipReader(t *testing.T, entries []declaredTarGzipTestEntry) *tar.Reader {
	t.Helper()
	var compressed bytes.Buffer
	gzipWriter := gzip.NewWriter(&compressed)
	tarWriter := tar.NewWriter(gzipWriter)
	for _, entry := range entries {
		typeFlag := entry.typeFlag
		if typeFlag == 0 {
			typeFlag = tar.TypeReg
		}
		header := &tar.Header{Name: entry.name, Typeflag: typeFlag, Mode: 0o755, Linkname: entry.symbolicLinkTarget}
		if typeFlag == tar.TypeReg || typeFlag == tar.TypeRegA {
			header.Size = int64(len(entry.contents))
		}
		if err := tarWriter.WriteHeader(header); err != nil {
			t.Fatalf("write tar header %q: %v", entry.name, err)
		}
		if header.Size > 0 {
			if _, err := tarWriter.Write([]byte(entry.contents)); err != nil {
				t.Fatalf("write tar contents %q: %v", entry.name, err)
			}
		}
	}
	if err := tarWriter.Close(); err != nil {
		t.Fatalf("close tar writer: %v", err)
	}
	if err := gzipWriter.Close(); err != nil {
		t.Fatalf("close gzip writer: %v", err)
	}
	gzipReader, err := gzip.NewReader(bytes.NewReader(compressed.Bytes()))
	if err != nil {
		t.Fatalf("open gzip reader: %v", err)
	}
	t.Cleanup(func() { _ = gzipReader.Close() })
	return tar.NewReader(gzipReader)
}
