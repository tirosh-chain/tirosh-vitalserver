// Package releaseeffectreceiptfile atomically publishes the C55 fact owned by
// the release effect executor. It never replaces different existing evidence.
package releaseeffectreceiptfile

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-effect-executor/internal/guestproductreleaseeffectexecutordomain"
)

const maximumReceiptBytes int64 = 1024 * 1024

func Write(path string, receipt guestproductreleaseeffectexecutordomain.StagedUpdateLayerEffectReceipt) error {
	if path == "" || !filepath.IsAbs(path) {
		return fmt.Errorf("C55 receipt path must be absolute")
	}
	directory := filepath.Dir(path)
	directoryInfo, err := os.Lstat(directory)
	if err != nil || !directoryInfo.IsDir() || directoryInfo.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("C55 receipt directory is missing, not a directory, or symbolic")
	}
	if existing, err := read(path); err == nil {
		if reflect.DeepEqual(existing, receipt) {
			return nil
		}
		return fmt.Errorf("C55 receipt path already contains different evidence")
	} else if !errors.Is(err, os.ErrNotExist) {
		return err
	}
	contents, err := json.Marshal(receipt)
	if err != nil {
		return fmt.Errorf("encode C55 receipt: %w", err)
	}
	contents = append(contents, '\n')
	temporary, err := os.CreateTemp(directory, ".guest-product-release-effect-receipt-")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err := temporary.Chmod(0o600); err != nil {
		temporary.Close()
		return err
	}
	if _, err := temporary.Write(contents); err != nil {
		temporary.Close()
		return err
	}
	if err := temporary.Sync(); err != nil {
		temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	if err := os.Link(temporaryPath, path); err == nil {
		return nil
	} else if !errors.Is(err, os.ErrExist) {
		return fmt.Errorf("publish C55 receipt without replacement: %w", err)
	}
	existing, err := read(path)
	if err != nil {
		return err
	}
	if !reflect.DeepEqual(existing, receipt) {
		return fmt.Errorf("C55 receipt path already contains different evidence")
	}
	return nil
}

func read(path string) (guestproductreleaseeffectexecutordomain.StagedUpdateLayerEffectReceipt, error) {
	info, err := os.Lstat(path)
	if err != nil {
		return guestproductreleaseeffectexecutordomain.StagedUpdateLayerEffectReceipt{}, err
	}
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return guestproductreleaseeffectexecutordomain.StagedUpdateLayerEffectReceipt{}, fmt.Errorf("C55 receipt is not a regular non-symbolic file")
	}
	if info.Size() > maximumReceiptBytes {
		return guestproductreleaseeffectexecutordomain.StagedUpdateLayerEffectReceipt{}, fmt.Errorf("C55 receipt exceeds maximum size")
	}
	file, err := os.Open(path)
	if err != nil {
		return guestproductreleaseeffectexecutordomain.StagedUpdateLayerEffectReceipt{}, err
	}
	defer file.Close()
	contents, err := io.ReadAll(io.LimitReader(file, maximumReceiptBytes+1))
	if err != nil {
		return guestproductreleaseeffectexecutordomain.StagedUpdateLayerEffectReceipt{}, err
	}
	if int64(len(contents)) > maximumReceiptBytes {
		return guestproductreleaseeffectexecutordomain.StagedUpdateLayerEffectReceipt{}, fmt.Errorf("C55 receipt exceeds maximum size")
	}
	decoder := json.NewDecoder(strings.NewReader(string(contents)))
	decoder.DisallowUnknownFields()
	var receipt guestproductreleaseeffectexecutordomain.StagedUpdateLayerEffectReceipt
	if err := decoder.Decode(&receipt); err != nil {
		return guestproductreleaseeffectexecutordomain.StagedUpdateLayerEffectReceipt{}, err
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return guestproductreleaseeffectexecutordomain.StagedUpdateLayerEffectReceipt{}, fmt.Errorf("C55 receipt must contain exactly one JSON document")
	}
	return receipt, nil
}
