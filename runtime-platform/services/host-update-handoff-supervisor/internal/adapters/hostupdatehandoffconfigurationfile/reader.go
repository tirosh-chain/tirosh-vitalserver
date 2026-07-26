// Package hostupdatehandoffconfigurationfile reads the deployment-owned C56
// document. It does not create a default configuration from a Host layout.
package hostupdatehandoffconfigurationfile

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-update-handoff-supervisor/internal/hostupdatehandoffsupervisordomain"
)

const maximumConfigurationBytes int64 = 1 << 20

var windowsAbsolutePath = regexp.MustCompile(`^[A-Za-z]:[\\/].*$`)

func ReadHostUpdateHandoffSupervisorConfiguration(path string) (hostupdatehandoffsupervisordomain.HostUpdateHandoffSupervisorConfiguration, error) {
	if !safeHostAbsolutePath(path) {
		return hostupdatehandoffsupervisordomain.HostUpdateHandoffSupervisorConfiguration{}, hostupdatehandoffsupervisordomain.DispatchFailure{State: "failed", Issue: hostupdatehandoffsupervisordomain.DispatchIssue{Code: "handoff-supervisor-configuration-path-invalid", Message: "C56 configuration path must be absolute without traversal", Dependency: "host-update-handoff-supervisor"}}
	}
	contents, err := readBoundedRegularFile(path, maximumConfigurationBytes)
	if err != nil {
		state := "failed"
		if errors.Is(err, os.ErrNotExist) || errors.Is(err, os.ErrPermission) {
			state = "unavailable"
		}
		return hostupdatehandoffsupervisordomain.HostUpdateHandoffSupervisorConfiguration{}, hostupdatehandoffsupervisordomain.DispatchFailure{State: state, Issue: hostupdatehandoffsupervisordomain.DispatchIssue{Code: "handoff-supervisor-configuration-unreadable", Message: err.Error(), Dependency: "host-update-handoff-supervisor"}}
	}
	var configuration hostupdatehandoffsupervisordomain.HostUpdateHandoffSupervisorConfiguration
	if err := decodeExactly(contents, &configuration); err != nil {
		return hostupdatehandoffsupervisordomain.HostUpdateHandoffSupervisorConfiguration{}, hostupdatehandoffsupervisordomain.DispatchFailure{State: "failed", Issue: hostupdatehandoffsupervisordomain.DispatchIssue{Code: "handoff-supervisor-configuration-invalid", Message: err.Error(), Dependency: "host-update-handoff-supervisor"}}
	}
	if err := hostupdatehandoffsupervisordomain.ValidateConfiguration(configuration); err != nil {
		return hostupdatehandoffsupervisordomain.HostUpdateHandoffSupervisorConfiguration{}, hostupdatehandoffsupervisordomain.DispatchFailure{State: "failed", Issue: hostupdatehandoffsupervisordomain.DispatchIssue{Code: "handoff-supervisor-configuration-invalid", Message: err.Error(), Dependency: "host-update-handoff-supervisor"}}
	}
	for _, candidate := range []string{configuration.StagingDirectory, configuration.HandoffQueueDirectory, configuration.ExecutionEvidenceDirectory, configuration.LayerEffectReceiptDirectory, configuration.HostLocalAdministrationDescriptorPath} {
		if !safeHostAbsolutePath(candidate) {
			return hostupdatehandoffsupervisordomain.HostUpdateHandoffSupervisorConfiguration{}, hostupdatehandoffsupervisordomain.DispatchFailure{State: "failed", Issue: hostupdatehandoffsupervisordomain.DispatchIssue{Code: "handoff-supervisor-configuration-invalid", Message: "C56 contains an invalid Host path", Dependency: "host-update-handoff-supervisor"}}
		}
	}
	return configuration, nil
}

func safeHostAbsolutePath(path string) bool {
	if path == "" || strings.TrimSpace(path) != path || strings.ContainsRune(path, '\x00') {
		return false
	}
	if !(filepath.IsAbs(path) || windowsAbsolutePath.MatchString(path)) {
		return false
	}
	for _, component := range strings.FieldsFunc(path, func(character rune) bool { return character == '/' || character == '\\' }) {
		if component == ".." {
			return false
		}
	}
	return true
}

func readBoundedRegularFile(path string, maximum int64) ([]byte, error) {
	info, err := os.Lstat(path)
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return nil, fmt.Errorf("file is not a regular non-symbolic-link file")
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	contents, err := io.ReadAll(io.LimitReader(file, maximum+1))
	if err != nil {
		return nil, err
	}
	if int64(len(contents)) > maximum {
		return nil, fmt.Errorf("file exceeds maximum size")
	}
	return contents, nil
}

func decodeExactly(contents []byte, output any) error {
	decoder := json.NewDecoder(strings.NewReader(string(contents)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(output); err != nil {
		return err
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return fmt.Errorf("document must contain exactly one JSON object")
	}
	return nil
}
