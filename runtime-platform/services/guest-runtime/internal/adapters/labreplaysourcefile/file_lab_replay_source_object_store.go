// Package labreplaysourcefile owns immutable user-uploaded Lab replay source
// bytes. It does not store Recorder uploads or Gateway cold-path artifacts.
package labreplaysourcefile

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

var ErrLabReplaySourceObjectConflict = errors.New("Lab replay source object conflict")

type FileLabReplaySourceObjectStore struct {
	stagingDirectory string
	objectsDirectory string
}

func OpenFileLabReplaySourceObjectStore(
	rootDirectory string,
) (*FileLabReplaySourceObjectStore, error) {
	if rootDirectory == "" {
		return nil, fmt.Errorf("Lab replay source object root directory is required")
	}
	store := &FileLabReplaySourceObjectStore{
		stagingDirectory: filepath.Join(rootDirectory, "staging"),
		objectsDirectory: filepath.Join(rootDirectory, "objects"),
	}
	for _, directory := range []string{
		store.stagingDirectory,
		store.objectsDirectory,
	} {
		if err := os.MkdirAll(directory, 0o700); err != nil {
			return nil, fmt.Errorf("create Lab replay source object directory: %w", err)
		}
	}
	return store, nil
}

func (store *FileLabReplaySourceObjectStore) CommitLabReplaySourceObject(
	ctx context.Context,
	commit guestruntimeapplication.LabReplaySourceObjectCommit,
) (guestruntimedomain.LabReplaySourceObjectReceipt, error) {
	if commit.Content == nil ||
		guestruntimedomain.ValidateLabReplaySourceAdmissionCommand(
			commit.Command,
			guestruntimedomain.MaximumLabReplaySourceByteSize,
		) != nil {
		return guestruntimedomain.LabReplaySourceObjectReceipt{},
			fmt.Errorf("Lab replay source object commit is incomplete or invalid")
	}
	finalDirectory := filepath.Join(
		store.objectsDirectory,
		commit.Command.SourceID,
	)
	if _, err := os.Stat(finalDirectory); err == nil {
		return store.readExistingReceipt(ctx, commit.Command, finalDirectory)
	} else if !errors.Is(err, os.ErrNotExist) {
		return guestruntimedomain.LabReplaySourceObjectReceipt{},
			fmt.Errorf("inspect Lab replay source object: %w", err)
	}
	transactionDirectory, err := os.MkdirTemp(
		store.stagingDirectory,
		commit.Command.SourceID+"-",
	)
	if err != nil {
		return guestruntimedomain.LabReplaySourceObjectReceipt{},
			fmt.Errorf("create Lab replay source transaction: %w", err)
	}
	defer os.RemoveAll(transactionDirectory)
	contentPath := filepath.Join(transactionDirectory, "content.vital")
	content, err := os.OpenFile(
		contentPath,
		os.O_WRONLY|os.O_CREATE|os.O_EXCL,
		0o600,
	)
	if err != nil {
		return guestruntimedomain.LabReplaySourceObjectReceipt{},
			fmt.Errorf("create Lab replay source content: %w", err)
	}
	hash := sha256.New()
	written, copyErr := io.Copy(
		io.MultiWriter(content, hash),
		io.LimitReader(commit.Content, commit.Command.ByteSize+1),
	)
	syncErr := content.Sync()
	closeErr := content.Close()
	if copyErr != nil {
		return guestruntimedomain.LabReplaySourceObjectReceipt{},
			fmt.Errorf("stream Lab replay source content: %w", copyErr)
	}
	if syncErr != nil {
		return guestruntimedomain.LabReplaySourceObjectReceipt{},
			fmt.Errorf("sync Lab replay source content: %w", syncErr)
	}
	if closeErr != nil {
		return guestruntimedomain.LabReplaySourceObjectReceipt{},
			fmt.Errorf("close Lab replay source content: %w", closeErr)
	}
	if err := ctx.Err(); err != nil {
		return guestruntimedomain.LabReplaySourceObjectReceipt{}, err
	}
	actualSHA256 := hex.EncodeToString(hash.Sum(nil))
	if written != commit.Command.ByteSize ||
		actualSHA256 != commit.Command.SHA256 {
		return guestruntimedomain.LabReplaySourceObjectReceipt{},
			guestruntimeapplication.ErrLabReplaySourceObjectContentMismatch
	}
	receipt := guestruntimedomain.LabReplaySourceObjectReceipt{
		SchemaVersion: guestruntimedomain.SchemaVersion,
		SourceReference: guestruntimedomain.ResourceReference{
			ResourceType: guestruntimedomain.LabReplaySourceResourceType,
			ResourceID:   commit.Command.SourceID,
		},
		State:    "committed",
		ByteSize: written,
		SHA256:   actualSHA256,
		StorageReference: guestruntimedomain.ResourceReference{
			ResourceType: guestruntimedomain.LabReplaySourceStorageType,
			ResourceID:   commit.Command.SourceID,
		},
		PersistedAt: commit.PersistedAt,
	}
	if err := guestruntimedomain.ValidateLabReplaySourceObjectReceipt(receipt); err != nil {
		return guestruntimedomain.LabReplaySourceObjectReceipt{}, err
	}
	if err := writeObjectReceipt(
		filepath.Join(transactionDirectory, "object-receipt.json"),
		receipt,
	); err != nil {
		return guestruntimedomain.LabReplaySourceObjectReceipt{}, err
	}
	if err := syncObjectDirectory(transactionDirectory); err != nil {
		return guestruntimedomain.LabReplaySourceObjectReceipt{},
			fmt.Errorf("sync Lab replay source transaction: %w", err)
	}
	if err := os.Rename(transactionDirectory, finalDirectory); err != nil {
		if _, statErr := os.Stat(finalDirectory); statErr == nil {
			return store.readExistingReceipt(ctx, commit.Command, finalDirectory)
		}
		return guestruntimedomain.LabReplaySourceObjectReceipt{},
			fmt.Errorf("commit Lab replay source transaction: %w", err)
	}
	if err := syncObjectDirectory(store.objectsDirectory); err != nil {
		return guestruntimedomain.LabReplaySourceObjectReceipt{},
			fmt.Errorf("sync Lab replay source owner directory: %w", err)
	}
	return receipt, nil
}

func (store *FileLabReplaySourceObjectStore) OpenLabReplaySourceObject(
	ctx context.Context,
	source guestruntimedomain.ResourceReference,
	expectedSHA256 string,
) (io.ReadCloser, error) {
	if source.ResourceType != guestruntimedomain.LabReplaySourceResourceType ||
		!guestruntimedomain.ValidIdentifier(source.ResourceID) ||
		len(expectedSHA256) != 64 {
		return nil, fmt.Errorf("Lab replay source object reference is invalid")
	}
	finalDirectory := filepath.Join(store.objectsDirectory, source.ResourceID)
	receipt, err := readObjectReceipt(finalDirectory)
	if err != nil {
		return nil, err
	}
	if receipt.SourceReference != source ||
		receipt.SHA256 != expectedSHA256 {
		return nil, ErrLabReplaySourceObjectConflict
	}
	if err := verifyContent(
		ctx,
		filepath.Join(finalDirectory, "content.vital"),
		receipt.ByteSize,
		receipt.SHA256,
	); err != nil {
		return nil, err
	}
	content, err := os.Open(filepath.Join(finalDirectory, "content.vital"))
	if err != nil {
		return nil, fmt.Errorf("open Lab replay source content: %w", err)
	}
	return content, nil
}

func (store *FileLabReplaySourceObjectStore) readExistingReceipt(
	ctx context.Context,
	command guestruntimedomain.LabReplaySourceAdmissionCommand,
	finalDirectory string,
) (guestruntimedomain.LabReplaySourceObjectReceipt, error) {
	receipt, err := readObjectReceipt(finalDirectory)
	if err != nil {
		return receipt, err
	}
	if receipt.SourceReference.ResourceID != command.SourceID ||
		receipt.ByteSize != command.ByteSize ||
		receipt.SHA256 != command.SHA256 {
		return receipt, ErrLabReplaySourceObjectConflict
	}
	if err := verifyContent(
		ctx,
		filepath.Join(finalDirectory, "content.vital"),
		receipt.ByteSize,
		receipt.SHA256,
	); err != nil {
		return receipt, err
	}
	receipt.State = "existing"
	return receipt, nil
}

func readObjectReceipt(
	finalDirectory string,
) (guestruntimedomain.LabReplaySourceObjectReceipt, error) {
	encoded, err := os.ReadFile(
		filepath.Join(finalDirectory, "object-receipt.json"),
	)
	if err != nil {
		return guestruntimedomain.LabReplaySourceObjectReceipt{},
			fmt.Errorf("read Lab replay source object receipt: %w", err)
	}
	var receipt guestruntimedomain.LabReplaySourceObjectReceipt
	if err := json.Unmarshal(encoded, &receipt); err != nil {
		return receipt, fmt.Errorf("decode Lab replay source object receipt: %w", err)
	}
	if err := guestruntimedomain.ValidateLabReplaySourceObjectReceipt(receipt); err != nil {
		return receipt, fmt.Errorf("validate Lab replay source object receipt: %w", err)
	}
	return receipt, nil
}

func verifyContent(
	ctx context.Context,
	path string,
	expectedByteSize int64,
	expectedSHA256 string,
) error {
	content, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("open Lab replay source object for verification: %w", err)
	}
	defer content.Close()
	hash := sha256.New()
	size, err := io.Copy(hash, content)
	if err != nil {
		return fmt.Errorf("verify Lab replay source object: %w", err)
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	if size != expectedByteSize ||
		hex.EncodeToString(hash.Sum(nil)) != expectedSHA256 {
		return guestruntimeapplication.ErrLabReplaySourceObjectContentMismatch
	}
	return nil
}

func writeObjectReceipt(
	path string,
	receipt guestruntimedomain.LabReplaySourceObjectReceipt,
) error {
	encoded, err := json.Marshal(receipt)
	if err != nil {
		return fmt.Errorf("encode Lab replay source object receipt: %w", err)
	}
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return fmt.Errorf("create Lab replay source object receipt: %w", err)
	}
	if _, err := file.Write(encoded); err != nil {
		_ = file.Close()
		return fmt.Errorf("write Lab replay source object receipt: %w", err)
	}
	if err := file.Sync(); err != nil {
		_ = file.Close()
		return fmt.Errorf("sync Lab replay source object receipt: %w", err)
	}
	if err := file.Close(); err != nil {
		return fmt.Errorf("close Lab replay source object receipt: %w", err)
	}
	return nil
}

func syncObjectDirectory(path string) error {
	directory, err := os.Open(path)
	if err != nil {
		return err
	}
	defer directory.Close()
	return directory.Sync()
}

var _ guestruntimeapplication.GuestRuntimeLabReplaySourceObjectStore = (*FileLabReplaySourceObjectStore)(nil)
