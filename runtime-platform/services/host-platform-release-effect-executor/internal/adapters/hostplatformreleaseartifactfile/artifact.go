package hostplatformreleaseartifactfile

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-platform-release-effect-executor/internal/hostplatformreleaseeffectexecutordomain"
)

func Inspect(path string, expectedSHA256 string) (hostplatformreleaseeffectexecutordomain.ReleaseArtifact, error) {
	if path == "" || !filepath.IsAbs(path) {
		return hostplatformreleaseeffectexecutordomain.ReleaseArtifact{}, fmt.Errorf("C67 Host Platform archive path is required")
	}
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || info.Size() < 1 {
		return hostplatformreleaseeffectexecutordomain.ReleaseArtifact{}, fmt.Errorf("C67 Host Platform archive is missing, non-regular, symbolic, or empty")
	}
	file, err := os.Open(path)
	if err != nil {
		return hostplatformreleaseeffectexecutordomain.ReleaseArtifact{}, fmt.Errorf("open C67 Host Platform archive: %w", err)
	}
	defer file.Close()
	digest := sha256.New()
	if _, err := io.Copy(digest, file); err != nil {
		return hostplatformreleaseeffectexecutordomain.ReleaseArtifact{}, fmt.Errorf("read C67 Host Platform archive: %w", err)
	}
	if actual := hex.EncodeToString(digest.Sum(nil)); actual != expectedSHA256 {
		return hostplatformreleaseeffectexecutordomain.ReleaseArtifact{}, fmt.Errorf("C67 Host Platform archive SHA256 differs from C26 declaration")
	}
	return hostplatformreleaseeffectexecutordomain.ReleaseArtifact{Path: path, SHA256: expectedSHA256, SizeBytes: info.Size()}, nil
}
