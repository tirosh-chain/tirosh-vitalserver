package hostlocalupdatecoordination

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type endpointDescriptor struct {
	SchemaVersion string `json:"schemaVersion"`
	Transport     string `json:"transport"`
	Address       string `json:"address"`
}

func openDescriptorClient(path string, timeout time.Duration) (endpointDescriptor, *http.Client, error) {
	if path == "" || !filepath.IsAbs(path) || timeout <= 0 {
		return endpointDescriptor{}, nil, fmt.Errorf("Host-local descriptor path and timeout are required")
	}
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return endpointDescriptor{}, nil, fmt.Errorf("Host-local descriptor is missing, non-regular, or symbolic")
	}
	file, err := os.Open(path)
	if err != nil {
		return endpointDescriptor{}, nil, err
	}
	defer file.Close()
	contents, err := io.ReadAll(io.LimitReader(file, maximumHostLocalResponseBytes+1))
	if err != nil || int64(len(contents)) > maximumHostLocalResponseBytes {
		return endpointDescriptor{}, nil, fmt.Errorf("Host-local descriptor is unreadable or oversized")
	}
	var descriptor endpointDescriptor
	if err := decodeExactly(contents, &descriptor); err != nil {
		return endpointDescriptor{}, nil, err
	}
	if descriptor.SchemaVersion != "v1" || descriptor.Address == "" {
		return endpointDescriptor{}, nil, fmt.Errorf("Host-local descriptor identity is invalid")
	}
	client, err := newDescriptorHTTPClient(descriptor, timeout)
	if err != nil {
		return endpointDescriptor{}, nil, err
	}
	return descriptor, client, nil
}

func decodeExactly(contents []byte, destination any) error {
	decoder := json.NewDecoder(strings.NewReader(string(contents)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		return err
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return fmt.Errorf("document must contain exactly one JSON object")
	}
	return nil
}
