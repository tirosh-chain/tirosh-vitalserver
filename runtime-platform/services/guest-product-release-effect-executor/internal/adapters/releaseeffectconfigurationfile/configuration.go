// Package releaseeffectconfigurationfile owns strict C61 filesystem decoding.
package releaseeffectconfigurationfile

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-effect-executor/internal/guestproductreleaseeffectexecutordomain"
)

const maximumConfigurationBytes int64 = 1024 * 1024

func Load(path string) (guestproductreleaseeffectexecutordomain.GuestProductReleaseEffectExecutorConfiguration, error) {
	if path == "" || !filepath.IsAbs(path) {
		return guestproductreleaseeffectexecutordomain.GuestProductReleaseEffectExecutorConfiguration{}, fmt.Errorf("C61 configuration path is required")
	}
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return guestproductreleaseeffectexecutordomain.GuestProductReleaseEffectExecutorConfiguration{}, fmt.Errorf("C61 configuration is missing, not regular, or symbolic")
	}
	if info.Size() > maximumConfigurationBytes {
		return guestproductreleaseeffectexecutordomain.GuestProductReleaseEffectExecutorConfiguration{}, fmt.Errorf("C61 configuration exceeds maximum size")
	}
	file, err := os.Open(path)
	if err != nil {
		return guestproductreleaseeffectexecutordomain.GuestProductReleaseEffectExecutorConfiguration{}, fmt.Errorf("open C61 configuration: %w", err)
	}
	defer file.Close()
	contents, err := io.ReadAll(io.LimitReader(file, maximumConfigurationBytes+1))
	if err != nil {
		return guestproductreleaseeffectexecutordomain.GuestProductReleaseEffectExecutorConfiguration{}, fmt.Errorf("read C61 configuration: %w", err)
	}
	if int64(len(contents)) > maximumConfigurationBytes {
		return guestproductreleaseeffectexecutordomain.GuestProductReleaseEffectExecutorConfiguration{}, fmt.Errorf("C61 configuration exceeds maximum size")
	}
	decoder := json.NewDecoder(strings.NewReader(string(contents)))
	decoder.DisallowUnknownFields()
	var configuration guestproductreleaseeffectexecutordomain.GuestProductReleaseEffectExecutorConfiguration
	if err := decoder.Decode(&configuration); err != nil {
		return guestproductreleaseeffectexecutordomain.GuestProductReleaseEffectExecutorConfiguration{}, fmt.Errorf("decode C61 configuration: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return guestproductreleaseeffectexecutordomain.GuestProductReleaseEffectExecutorConfiguration{}, fmt.Errorf("C61 configuration contains multiple documents")
	}
	if err := guestproductreleaseeffectexecutordomain.ValidateConfiguration(configuration); err != nil {
		return guestproductreleaseeffectexecutordomain.GuestProductReleaseEffectExecutorConfiguration{}, err
	}
	return configuration, nil
}
