// Package guestbootstrapidentityfile owns the explicit filesystem reads used
// to prove persistent Guest bootstrap evidence. It never exposes material
// values or derives bootstrap success from file presence alone.
package guestbootstrapidentityfile

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

const privateEvidenceMaximumBytes = 64 * 1024

type Configuration struct {
	MigrationReceiptPath                          string
	RecorderCatalogDatabaseURLMaterialPath        string
	CatalogAdmissionBearerTokenMaterialPath       string
	ArchiveSourceAdmissionBearerTokenMaterialPath string
}

type Reader struct {
	configuration Configuration
}

func NewReader(configuration Configuration) (*Reader, error) {
	paths := []string{
		configuration.MigrationReceiptPath,
		configuration.RecorderCatalogDatabaseURLMaterialPath,
		configuration.CatalogAdmissionBearerTokenMaterialPath,
		configuration.ArchiveSourceAdmissionBearerTokenMaterialPath,
	}
	seen := map[string]struct{}{}
	for _, path := range paths {
		if path == "" || !filepath.IsAbs(path) || filepath.Clean(path) != path {
			return nil, fmt.Errorf("Guest bootstrap identity paths must be explicit absolute paths without traversal")
		}
		if _, duplicate := seen[path]; duplicate {
			return nil, fmt.Errorf("Guest bootstrap identity paths must be distinct")
		}
		seen[path] = struct{}{}
	}
	return &Reader{configuration: configuration}, nil
}

func (reader *Reader) ReadGuestOperationalStateBootstrapIdentity(
	ctx context.Context,
) (guestruntimedomain.GuestOperationalStateBootstrapIdentity, error) {
	if err := ctx.Err(); err != nil {
		return guestruntimedomain.GuestOperationalStateBootstrapIdentity{}, err
	}
	receiptBytes, err := readPrivateEvidenceFile(
		reader.configuration.MigrationReceiptPath,
		"Recorder Catalog migration receipt",
	)
	if err != nil {
		return guestruntimedomain.GuestOperationalStateBootstrapIdentity{}, err
	}
	var receipt guestruntimedomain.GuestOperationalStateMigrationReceipt
	decoder := json.NewDecoder(bytes.NewReader(receiptBytes))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&receipt); err != nil {
		return guestruntimedomain.GuestOperationalStateBootstrapIdentity{},
			fmt.Errorf("Recorder Catalog migration receipt decode failed: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return guestruntimedomain.GuestOperationalStateBootstrapIdentity{},
			fmt.Errorf("Recorder Catalog migration receipt must contain one JSON value")
	}

	materials := []struct {
		label string
		path  string
	}{
		{
			label: "recorder-catalog-database-url",
			path:  reader.configuration.RecorderCatalogDatabaseURLMaterialPath,
		},
		{
			label: "recorder-catalog-admission-token",
			path:  reader.configuration.CatalogAdmissionBearerTokenMaterialPath,
		},
		{
			label: "archive-source-admission-token",
			path:  reader.configuration.ArchiveSourceAdmissionBearerTokenMaterialPath,
		},
	}
	digest := sha256.New()
	for _, material := range materials {
		if err := ctx.Err(); err != nil {
			return guestruntimedomain.GuestOperationalStateBootstrapIdentity{}, err
		}
		value, err := readPrivateEvidenceFile(material.path, material.label)
		if err != nil {
			return guestruntimedomain.GuestOperationalStateBootstrapIdentity{}, err
		}
		writeDigestFrame(digest, []byte(material.label))
		writeDigestFrame(digest, value)
	}
	identity := guestruntimedomain.GuestOperationalStateBootstrapIdentity{
		MigrationReceipt: receipt,
		PrivateMaterialSet: guestruntimedomain.GuestOperationalStatePrivateMaterialSetIdentity{
			MaterialCount: len(materials),
			SHA256:        hex.EncodeToString(digest.Sum(nil)),
		},
	}
	if err := guestruntimedomain.ValidateGuestOperationalStateBootstrapIdentity(
		identity,
		receipt.Revision,
	); err != nil {
		return guestruntimedomain.GuestOperationalStateBootstrapIdentity{}, err
	}
	return identity, nil
}

func readPrivateEvidenceFile(path string, description string) ([]byte, error) {
	info, err := os.Lstat(path)
	if err != nil {
		return nil, fmt.Errorf("%s read failed: %w", description, err)
	}
	if !info.Mode().IsRegular() || info.Mode().Perm()&0o077 != 0 ||
		info.Size() < 1 || info.Size() > privateEvidenceMaximumBytes {
		return nil, fmt.Errorf(
			"%s must be one private regular file between 1 and %d bytes",
			description,
			privateEvidenceMaximumBytes,
		)
	}
	value, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("%s read failed: %w", description, err)
	}
	return value, nil
}

func writeDigestFrame(writer io.Writer, value []byte) {
	var length [8]byte
	binary.BigEndian.PutUint64(length[:], uint64(len(value)))
	_, _ = writer.Write(length[:])
	_, _ = writer.Write(value)
}
