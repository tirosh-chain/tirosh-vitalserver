package imageseteffectreceiptfile

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-effect-executor/internal/guestbundledupstreamimageseteffectexecutordomain"
)

func Write(path string, receipt guestbundledupstreamimageseteffectexecutordomain.StagedUpdateLayerEffectReceipt) error {
	if path == "" || !filepath.IsAbs(path) { return fmt.Errorf("C55 receipt path is required") }
	if receipt.SchemaVersion != "v1" || receipt.UpdateID == "" || receipt.Layer != "bundled-upstream" || receipt.EffectExecutorID == "" || receipt.Operation == "" || receipt.ArtifactSHA256 == "" || receipt.State == "" || receipt.ObservedAt == "" || receipt.Evidence.Kind == "" || receipt.Evidence.ID == "" { return fmt.Errorf("C55 C66 receipt is invalid") }
	if info, err := os.Lstat(path); err == nil || !os.IsNotExist(err) { if err == nil && info != nil { return fmt.Errorf("C55 receipt output already exists") }; return err }
	contents, err := json.Marshal(receipt); if err != nil { return err }
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil { return err }
	temporary, err := os.CreateTemp(filepath.Dir(path), ".c55-image-set-receipt.*.tmp"); if err != nil { return err }; temporaryPath := temporary.Name(); defer os.Remove(temporaryPath)
	if err := temporary.Chmod(0o600); err != nil { temporary.Close(); return err }; if _, err := temporary.Write(append(contents, '\n')); err != nil { temporary.Close(); return err }; if err := temporary.Sync(); err != nil { temporary.Close(); return err }; if err := temporary.Close(); err != nil { return err }; return os.Rename(temporaryPath, path)
}
