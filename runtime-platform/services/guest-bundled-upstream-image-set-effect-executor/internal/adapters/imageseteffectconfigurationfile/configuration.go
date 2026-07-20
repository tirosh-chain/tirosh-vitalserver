package imageseteffectconfigurationfile

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-effect-executor/internal/guestbundledupstreamimageseteffectexecutordomain"
)

const maximumConfigurationBytes int64 = 1024 * 1024

func Load(path string) (guestbundledupstreamimageseteffectexecutordomain.ImageSetEffectExecutorConfiguration, error) {
	if path == "" || !filepath.IsAbs(path) { return guestbundledupstreamimageseteffectexecutordomain.ImageSetEffectExecutorConfiguration{}, fmt.Errorf("C66 configuration path is required") }
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 { return guestbundledupstreamimageseteffectexecutordomain.ImageSetEffectExecutorConfiguration{}, fmt.Errorf("C66 configuration is missing, not regular, or symbolic") }
	if info.Size() > maximumConfigurationBytes { return guestbundledupstreamimageseteffectexecutordomain.ImageSetEffectExecutorConfiguration{}, fmt.Errorf("C66 configuration exceeds maximum size") }
	file, err := os.Open(path); if err != nil { return guestbundledupstreamimageseteffectexecutordomain.ImageSetEffectExecutorConfiguration{}, fmt.Errorf("open C66 configuration: %w", err) }; defer file.Close()
	contents, err := io.ReadAll(io.LimitReader(file, maximumConfigurationBytes+1)); if err != nil { return guestbundledupstreamimageseteffectexecutordomain.ImageSetEffectExecutorConfiguration{}, fmt.Errorf("read C66 configuration: %w", err) }; if int64(len(contents)) > maximumConfigurationBytes { return guestbundledupstreamimageseteffectexecutordomain.ImageSetEffectExecutorConfiguration{}, fmt.Errorf("C66 configuration exceeds maximum size") }
	decoder := json.NewDecoder(strings.NewReader(string(contents))); decoder.DisallowUnknownFields()
	var value guestbundledupstreamimageseteffectexecutordomain.ImageSetEffectExecutorConfiguration
	if err := decoder.Decode(&value); err != nil { return guestbundledupstreamimageseteffectexecutordomain.ImageSetEffectExecutorConfiguration{}, fmt.Errorf("decode C66 configuration: %w", err) }
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) { return guestbundledupstreamimageseteffectexecutordomain.ImageSetEffectExecutorConfiguration{}, fmt.Errorf("C66 configuration contains multiple documents") }
	if err := guestbundledupstreamimageseteffectexecutordomain.ValidateConfiguration(value); err != nil { return guestbundledupstreamimageseteffectexecutordomain.ImageSetEffectExecutorConfiguration{}, err }
	return value, nil
}
