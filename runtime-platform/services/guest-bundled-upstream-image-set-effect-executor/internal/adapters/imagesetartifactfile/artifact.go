package imagesetartifactfile

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-effect-executor/internal/guestbundledupstreamimageseteffectexecutordomain"
)

func Inspect(path string, expectedSHA256 string) (guestbundledupstreamimageseteffectexecutordomain.ReleaseArtifact, error) {
	if path == "" || !filepath.IsAbs(path) { return guestbundledupstreamimageseteffectexecutordomain.ReleaseArtifact{}, fmt.Errorf("C66 image-set artifact path is required") }
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || info.Size() < 1 { return guestbundledupstreamimageseteffectexecutordomain.ReleaseArtifact{}, fmt.Errorf("C66 image-set artifact is missing, non-regular, symbolic, or empty") }
	file, err := os.Open(path); if err != nil { return guestbundledupstreamimageseteffectexecutordomain.ReleaseArtifact{}, fmt.Errorf("open C66 image-set artifact: %w", err) }; defer file.Close()
	digest := sha256.New(); if _, err := io.Copy(digest, file); err != nil { return guestbundledupstreamimageseteffectexecutordomain.ReleaseArtifact{}, fmt.Errorf("read C66 image-set artifact: %w", err) }
	if actual := hex.EncodeToString(digest.Sum(nil)); actual != expectedSHA256 { return guestbundledupstreamimageseteffectexecutordomain.ReleaseArtifact{}, fmt.Errorf("C66 image-set artifact SHA256 differs from C26 declaration") }
	return guestbundledupstreamimageseteffectexecutordomain.ReleaseArtifact{Path: path, SHA256: expectedSHA256, SizeBytes: info.Size()}, nil
}
