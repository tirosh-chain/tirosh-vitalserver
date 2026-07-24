// Package archiveartifactobjectfile owns direct-upload .vital object bytes on
// the Guest filesystem.
package archiveartifactobjectfile

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

var ErrArchiveArtifactObjectConflict = errors.New("Archive artifact object conflict")

type FileArchiveArtifactObjectStore struct {
	stagingDirectory string
	objectsDirectory string
}

func OpenFileArchiveArtifactObjectStore(
	rootDirectory string,
) (*FileArchiveArtifactObjectStore, error) {
	if rootDirectory == "" {
		return nil, fmt.Errorf("Archive artifact object root directory is required")
	}
	store := &FileArchiveArtifactObjectStore{
		stagingDirectory: filepath.Join(rootDirectory, "staging"),
		objectsDirectory: filepath.Join(rootDirectory, "objects"),
	}
	for _, directory := range []string{
		store.stagingDirectory,
		store.objectsDirectory,
	} {
		if err := os.MkdirAll(directory, 0o700); err != nil {
			return nil, fmt.Errorf("create Archive artifact object directory: %w", err)
		}
	}
	return store, nil
}

func (store *FileArchiveArtifactObjectStore) CommitArchiveArtifactObject(
	ctx context.Context,
	commit guestruntimeapplication.ArchiveArtifactObjectCommit,
) (guestruntimedomain.ArchiveArtifactObjectReceipt, error) {
	if commit.Content == nil ||
		commit.PersistedAt == "" ||
		guestruntimedomain.ValidateRecorderVitalUploadSourceReceipt(commit.Source) != nil {
		return guestruntimedomain.ArchiveArtifactObjectReceipt{},
			fmt.Errorf("Archive artifact object commit is incomplete or invalid")
	}
	expectedArtifactID, err := guestruntimedomain.ArchiveArtifactIDForSourceReceipt(
		commit.Source.SourceKind,
		guestruntimedomain.RecorderVitalUploadSourceReceiptType,
		commit.Source.ID,
	)
	if err != nil || expectedArtifactID != commit.ArtifactID {
		return guestruntimedomain.ArchiveArtifactObjectReceipt{},
			fmt.Errorf("Archive artifact object identity does not match source receipt")
	}
	finalDirectory := filepath.Join(store.objectsDirectory, commit.ArtifactID)
	if _, err := os.Stat(finalDirectory); err == nil {
		return store.readExistingReceipt(commit, finalDirectory)
	} else if !errors.Is(err, os.ErrNotExist) {
		return guestruntimedomain.ArchiveArtifactObjectReceipt{},
			fmt.Errorf("inspect Archive artifact object: %w", err)
	}

	transactionDirectory, err := os.MkdirTemp(
		store.stagingDirectory,
		commit.ArtifactID+"-",
	)
	if err != nil {
		return guestruntimedomain.ArchiveArtifactObjectReceipt{},
			fmt.Errorf("create Archive artifact object transaction: %w", err)
	}
	defer os.RemoveAll(transactionDirectory)
	contentPath := filepath.Join(transactionDirectory, "content.vital")
	content, err := os.OpenFile(contentPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return guestruntimedomain.ArchiveArtifactObjectReceipt{},
			fmt.Errorf("create Archive artifact content: %w", err)
	}
	hash := sha256.New()
	written, copyErr := io.Copy(
		io.MultiWriter(content, hash),
		io.LimitReader(commit.Content, commit.Source.ByteSize+1),
	)
	syncErr := content.Sync()
	closeErr := content.Close()
	if copyErr != nil {
		return guestruntimedomain.ArchiveArtifactObjectReceipt{},
			fmt.Errorf("stream Archive artifact content: %w", copyErr)
	}
	if syncErr != nil {
		return guestruntimedomain.ArchiveArtifactObjectReceipt{},
			fmt.Errorf("sync Archive artifact content: %w", syncErr)
	}
	if closeErr != nil {
		return guestruntimedomain.ArchiveArtifactObjectReceipt{},
			fmt.Errorf("close Archive artifact content: %w", closeErr)
	}
	if err := ctx.Err(); err != nil {
		return guestruntimedomain.ArchiveArtifactObjectReceipt{}, err
	}
	actualSHA256 := hex.EncodeToString(hash.Sum(nil))
	if written != commit.Source.ByteSize ||
		actualSHA256 != commit.Source.SHA256 {
		return guestruntimedomain.ArchiveArtifactObjectReceipt{},
			guestruntimeapplication.ErrArchiveArtifactObjectContentMismatch
	}
	receipt := guestruntimedomain.ArchiveArtifactObjectReceipt{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		ArtifactID:    commit.ArtifactID,
		State:         "committed",
		ByteSize:      written,
		SHA256:        actualSHA256,
		StorageReference: guestruntimedomain.ResourceReference{
			ResourceType: "guest-archive-object",
			ResourceID:   commit.ArtifactID,
		},
		PersistedAt: commit.PersistedAt,
	}
	if err := guestruntimedomain.ValidateArchiveArtifactObjectReceipt(receipt); err != nil {
		return guestruntimedomain.ArchiveArtifactObjectReceipt{}, err
	}
	if err := writeReceipt(
		filepath.Join(transactionDirectory, "object-receipt.json"),
		receipt,
	); err != nil {
		return guestruntimedomain.ArchiveArtifactObjectReceipt{}, err
	}
	if err := syncDirectory(transactionDirectory); err != nil {
		return guestruntimedomain.ArchiveArtifactObjectReceipt{},
			fmt.Errorf("sync Archive artifact object transaction: %w", err)
	}
	if err := os.Rename(transactionDirectory, finalDirectory); err != nil {
		if _, statErr := os.Stat(finalDirectory); statErr == nil {
			return store.readExistingReceipt(commit, finalDirectory)
		}
		return guestruntimedomain.ArchiveArtifactObjectReceipt{},
			fmt.Errorf("commit Archive artifact object transaction: %w", err)
	}
	if err := syncDirectory(store.objectsDirectory); err != nil {
		return guestruntimedomain.ArchiveArtifactObjectReceipt{},
			fmt.Errorf("sync Archive artifact object owner directory: %w", err)
	}
	return receipt, nil
}

func (store *FileArchiveArtifactObjectStore) readExistingReceipt(
	commit guestruntimeapplication.ArchiveArtifactObjectCommit,
	finalDirectory string,
) (guestruntimedomain.ArchiveArtifactObjectReceipt, error) {
	encoded, err := os.ReadFile(filepath.Join(finalDirectory, "object-receipt.json"))
	if err != nil {
		return guestruntimedomain.ArchiveArtifactObjectReceipt{},
			fmt.Errorf("read existing Archive artifact object receipt: %w", err)
	}
	var receipt guestruntimedomain.ArchiveArtifactObjectReceipt
	if err := json.Unmarshal(encoded, &receipt); err != nil {
		return receipt, fmt.Errorf("decode existing Archive artifact object receipt: %w", err)
	}
	if err := guestruntimedomain.ValidateArchiveArtifactObjectReceipt(receipt); err != nil {
		return receipt, fmt.Errorf("validate existing Archive artifact object receipt: %w", err)
	}
	if receipt.State != "committed" ||
		receipt.ArtifactID != commit.ArtifactID ||
		receipt.ByteSize != commit.Source.ByteSize ||
		receipt.SHA256 != commit.Source.SHA256 {
		return receipt, ErrArchiveArtifactObjectConflict
	}
	content, err := os.Open(filepath.Join(finalDirectory, "content.vital"))
	if err != nil {
		return receipt, fmt.Errorf("open existing Archive artifact content: %w", err)
	}
	defer content.Close()
	hash := sha256.New()
	size, err := io.Copy(hash, content)
	if err != nil {
		return receipt, fmt.Errorf("verify existing Archive artifact content: %w", err)
	}
	if size != receipt.ByteSize ||
		hex.EncodeToString(hash.Sum(nil)) != receipt.SHA256 {
		return receipt, guestruntimeapplication.ErrArchiveArtifactObjectContentMismatch
	}
	receipt.State = "existing"
	return receipt, nil
}

func writeReceipt(
	path string,
	receipt guestruntimedomain.ArchiveArtifactObjectReceipt,
) error {
	encoded, err := json.Marshal(receipt)
	if err != nil {
		return fmt.Errorf("encode Archive artifact object receipt: %w", err)
	}
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return fmt.Errorf("create Archive artifact object receipt: %w", err)
	}
	if _, err := file.Write(encoded); err != nil {
		_ = file.Close()
		return fmt.Errorf("write Archive artifact object receipt: %w", err)
	}
	if err := file.Sync(); err != nil {
		_ = file.Close()
		return fmt.Errorf("sync Archive artifact object receipt: %w", err)
	}
	if err := file.Close(); err != nil {
		return fmt.Errorf("close Archive artifact object receipt: %w", err)
	}
	return nil
}

func syncDirectory(path string) error {
	directory, err := os.Open(path)
	if err != nil {
		return err
	}
	defer directory.Close()
	return directory.Sync()
}

var _ guestruntimeapplication.GuestRuntimeArchiveArtifactObjectStore = (*FileArchiveArtifactObjectStore)(nil)
