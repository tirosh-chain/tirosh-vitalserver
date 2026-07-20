// Package releaseartifactfile owns explicit inspection of the Host-staged
// archive passed by the fixed C26 protocol.
package releaseartifactfile

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-effect-executor/internal/guestproductreleaseeffectexecutordomain"
)

func Inspect(path string, expectedSHA256 string) (guestproductreleaseeffectexecutordomain.ReleaseArtifact, error) {
	if path == "" || !filepath.IsAbs(path) {
		return guestproductreleaseeffectexecutordomain.ReleaseArtifact{}, fmt.Errorf("C55 artifact path must be absolute")
	}
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || info.Size() < 1 {
		return guestproductreleaseeffectexecutordomain.ReleaseArtifact{}, fmt.Errorf("C55 artifact is missing, not regular, symbolic, or empty")
	}
	file, err := os.Open(path)
	if err != nil {
		return guestproductreleaseeffectexecutordomain.ReleaseArtifact{}, fmt.Errorf("open C55 artifact: %w", err)
	}
	defer file.Close()
	digest := sha256.New()
	if _, err := io.Copy(digest, file); err != nil {
		return guestproductreleaseeffectexecutordomain.ReleaseArtifact{}, fmt.Errorf("read C55 artifact: %w", err)
	}
	actualSHA256 := hex.EncodeToString(digest.Sum(nil))
	if actualSHA256 != expectedSHA256 {
		return guestproductreleaseeffectexecutordomain.ReleaseArtifact{}, fmt.Errorf("C55 artifact sha256 does not match fixed protocol")
	}
	return guestproductreleaseeffectexecutordomain.ReleaseArtifact{Path: path, SHA256: actualSHA256, SizeBytes: info.Size()}, nil
}
