// Package updateexecutionreportfile reads an explicit C28 report produced by a
// selected update layer effect executor. It does not infer a report from logs,
// exit status, or an absent artifact.
package updateexecutionreportfile

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-updater/internal/hostupdaterdomain"
)

const maximumReportBytes int64 = 1 << 20

// StagedProductUpdateExecutionReportFileReader is the filesystem adapter for
// one named C28 staged product-update execution evidence document.
type StagedProductUpdateExecutionReportFileReader struct{}

func (StagedProductUpdateExecutionReportFileReader) Read(path string) (hostupdaterdomain.StagedProductUpdateExecutionReport, error) {
	if path == "" {
		return hostupdaterdomain.StagedProductUpdateExecutionReport{}, fmt.Errorf("C28 report path is required")
	}
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return hostupdaterdomain.StagedProductUpdateExecutionReport{}, fmt.Errorf("C28 report file is missing, not regular, or a symlink")
	}
	file, err := os.Open(path)
	if err != nil {
		return hostupdaterdomain.StagedProductUpdateExecutionReport{}, fmt.Errorf("open C28 report: %w", err)
	}
	defer file.Close()
	contents, err := io.ReadAll(io.LimitReader(file, maximumReportBytes+1))
	if err != nil {
		return hostupdaterdomain.StagedProductUpdateExecutionReport{}, fmt.Errorf("read C28 report: %w", err)
	}
	if int64(len(contents)) > maximumReportBytes {
		return hostupdaterdomain.StagedProductUpdateExecutionReport{}, fmt.Errorf("C28 report exceeds maximum document size")
	}
	decoder := json.NewDecoder(strings.NewReader(string(contents)))
	decoder.DisallowUnknownFields()
	var report hostupdaterdomain.StagedProductUpdateExecutionReport
	if err := decoder.Decode(&report); err != nil {
		return hostupdaterdomain.StagedProductUpdateExecutionReport{}, fmt.Errorf("decode C28 report: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return hostupdaterdomain.StagedProductUpdateExecutionReport{}, fmt.Errorf("C28 report must contain exactly one JSON object")
	}
	return report, nil
}
