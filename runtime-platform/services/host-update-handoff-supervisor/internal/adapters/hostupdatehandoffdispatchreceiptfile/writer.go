// Package hostupdatehandoffdispatchreceiptfile publishes immutable C57
// dispatch evidence. A later attempt must use a new attempt ID; it cannot
// replace historical dispatch meaning.
package hostupdatehandoffdispatchreceiptfile

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-update-handoff-supervisor/internal/hostupdatehandoffsupervisordomain"
)

func WriteHostUpdateHandoffDispatchReceipt(directory string, receipt hostupdatehandoffsupervisordomain.HostUpdateHandoffDispatchReceipt) (string, error) {
	if directory == "" || !filepath.IsAbs(directory) || receipt.AttemptID == "" {
		return "", fmt.Errorf("absolute C57 receipt directory and attempt id are required")
	}
	if err := ensureDirectoryWithoutSymlink(directory); err != nil {
		return "", err
	}
	path := filepath.Join(directory, "dispatch-attempts", receipt.AttemptID+".json")
	if err := ensureDirectoryWithoutSymlink(filepath.Dir(path)); err != nil {
		return "", err
	}
	encoded, err := json.Marshal(receipt)
	if err != nil {
		return "", err
	}
	if existing, exists, err := readReceipt(path); err != nil {
		return "", err
	} else if exists {
		if !reflect.DeepEqual(existing, receipt) {
			return "", fmt.Errorf("existing C57 receipt has different evidence")
		}
		return path, nil
	}
	temporary, err := os.CreateTemp(filepath.Dir(path), "."+receipt.AttemptID+".receipt-")
	if err != nil {
		return "", err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err := temporary.Chmod(0o600); err != nil {
		temporary.Close()
		return "", err
	}
	if _, err := temporary.Write(encoded); err != nil {
		temporary.Close()
		return "", err
	}
	if err := temporary.Sync(); err != nil {
		temporary.Close()
		return "", err
	}
	if err := temporary.Close(); err != nil {
		return "", err
	}
	if err := os.Link(temporaryPath, path); err != nil {
		if errors.Is(err, os.ErrExist) {
			existing, exists, readErr := readReceipt(path)
			if readErr != nil {
				return "", readErr
			}
			if !exists || !reflect.DeepEqual(existing, receipt) {
				return "", fmt.Errorf("existing C57 receipt has different evidence")
			}
			return path, nil
		}
		return "", err
	}
	if err := syncDirectory(filepath.Dir(path)); err != nil {
		return "", err
	}
	return path, nil
}

// ReadHostUpdateHandoffDispatchReceipt returns one immutable C57 attempt
// result.  The supervisor uses this before dispatching an automatically named
// attempt so a restart cannot silently execute the same C31 handoff twice.
// A missing receipt is an explicit non-result, not a failed update.
func ReadHostUpdateHandoffDispatchReceipt(directory string, attemptID string) (hostupdatehandoffsupervisordomain.HostUpdateHandoffDispatchReceipt, bool, error) {
	if directory == "" || !filepath.IsAbs(directory) || attemptID == "" {
		return hostupdatehandoffsupervisordomain.HostUpdateHandoffDispatchReceipt{}, false, fmt.Errorf("absolute C57 receipt directory and attempt id are required")
	}
	if err := ensureDirectoryWithoutSymlink(directory); err != nil {
		return hostupdatehandoffsupervisordomain.HostUpdateHandoffDispatchReceipt{}, false, err
	}
	return readReceipt(filepath.Join(directory, "dispatch-attempts", attemptID+".json"))
}

func ensureDirectoryWithoutSymlink(path string) error {
	abs, err := filepath.Abs(path)
	if err != nil {
		return err
	}
	current := string(filepath.Separator)
	if volume := filepath.VolumeName(abs); volume != "" {
		current = volume + string(filepath.Separator)
	}
	for _, component := range splitPath(abs) {
		current = filepath.Join(current, component)
		info, err := os.Lstat(current)
		if errors.Is(err, os.ErrNotExist) {
			if err := os.Mkdir(current, 0o700); err != nil && !errors.Is(err, os.ErrExist) {
				return err
			}
			continue
		}
		if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("receipt directory contains a missing, non-directory, or symbolic-link path component")
		}
	}
	return nil
}

func splitPath(path string) []string {
	volume := filepath.VolumeName(path)
	trimmed := path[len(volume):]
	trimmed = filepath.Clean(trimmed)
	components := []string{}
	for _, component := range strings.FieldsFunc(trimmed, func(character rune) bool { return character == '/' || character == '\\' }) {
		if component != "" {
			components = append(components, component)
		}
	}
	return components
}

func readReceipt(path string) (hostupdatehandoffsupervisordomain.HostUpdateHandoffDispatchReceipt, bool, error) {
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return hostupdatehandoffsupervisordomain.HostUpdateHandoffDispatchReceipt{}, false, nil
	}
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return hostupdatehandoffsupervisordomain.HostUpdateHandoffDispatchReceipt{}, false, fmt.Errorf("C57 receipt is missing, non-regular, or a symbolic link")
	}
	contents, err := os.ReadFile(path)
	if err != nil {
		return hostupdatehandoffsupervisordomain.HostUpdateHandoffDispatchReceipt{}, false, err
	}
	var receipt hostupdatehandoffsupervisordomain.HostUpdateHandoffDispatchReceipt
	decoder := json.NewDecoder(strings.NewReader(string(contents)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&receipt); err != nil {
		return hostupdatehandoffsupervisordomain.HostUpdateHandoffDispatchReceipt{}, false, err
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return hostupdatehandoffsupervisordomain.HostUpdateHandoffDispatchReceipt{}, false, fmt.Errorf("C57 receipt must contain exactly one JSON object")
	}
	return receipt, true, nil
}

func syncDirectory(path string) error {
	directory, err := os.Open(path)
	if err != nil {
		return err
	}
	defer directory.Close()
	return directory.Sync()
}
