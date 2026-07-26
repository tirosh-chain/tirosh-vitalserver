package hostplatformreleaseeffectconfigurationfile

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-platform-release-effect-executor/internal/hostplatformreleaseeffectexecutordomain"
)

const maximumConfigurationBytes int64 = 1024 * 1024

func Load(path string) (hostplatformreleaseeffectexecutordomain.EffectExecutorConfiguration, error) {
	if path == "" || !filepath.IsAbs(path) {
		return hostplatformreleaseeffectexecutordomain.EffectExecutorConfiguration{}, fmt.Errorf("C67 configuration path is required")
	}
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return hostplatformreleaseeffectexecutordomain.EffectExecutorConfiguration{}, fmt.Errorf("C67 configuration is missing, not regular, or symbolic")
	}
	if info.Size() > maximumConfigurationBytes {
		return hostplatformreleaseeffectexecutordomain.EffectExecutorConfiguration{}, fmt.Errorf("C67 configuration exceeds maximum size")
	}
	file, err := os.Open(path)
	if err != nil {
		return hostplatformreleaseeffectexecutordomain.EffectExecutorConfiguration{}, fmt.Errorf("open C67 configuration: %w", err)
	}
	defer file.Close()
	contents, err := io.ReadAll(io.LimitReader(file, maximumConfigurationBytes+1))
	if err != nil {
		return hostplatformreleaseeffectexecutordomain.EffectExecutorConfiguration{}, fmt.Errorf("read C67 configuration: %w", err)
	}
	if int64(len(contents)) > maximumConfigurationBytes {
		return hostplatformreleaseeffectexecutordomain.EffectExecutorConfiguration{}, fmt.Errorf("C67 configuration exceeds maximum size")
	}
	decoder := json.NewDecoder(strings.NewReader(string(contents)))
	decoder.DisallowUnknownFields()
	var value hostplatformreleaseeffectexecutordomain.EffectExecutorConfiguration
	if err := decoder.Decode(&value); err != nil {
		return hostplatformreleaseeffectexecutordomain.EffectExecutorConfiguration{}, fmt.Errorf("decode C67 configuration: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return hostplatformreleaseeffectexecutordomain.EffectExecutorConfiguration{}, fmt.Errorf("C67 configuration contains multiple documents")
	}
	if err := hostplatformreleaseeffectexecutordomain.ValidateConfiguration(value); err != nil {
		return hostplatformreleaseeffectexecutordomain.EffectExecutorConfiguration{}, err
	}
	return value, nil
}
