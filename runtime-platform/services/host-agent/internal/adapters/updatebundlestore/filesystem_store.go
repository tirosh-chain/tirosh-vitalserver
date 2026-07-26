// Package updatebundlestore owns the Host-local immutable offline update
// bundle store.  It accepts a regular directory selected by an authorized
// local operator and publishes only complete, non-symlinked bundle trees.
package updatebundlestore

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

const bootstrapEnvelopeFilename = "bootstrap-envelope.json"

// FileSystemStoreConfig identifies an already-provisioned private Host
// directory.  The store never creates a missing root because that would turn a
// missing C33 installation prerequisite into a successful update path.
type FileSystemStoreConfig struct {
	Directory string
	Clock     hostagentapplication.HostAgentClock
}

type FileSystemStore struct {
	directory string
	clock     hostagentapplication.HostAgentClock
}

func NewFileSystemStore(config FileSystemStoreConfig) (*FileSystemStore, error) {
	if config.Directory == "" || config.Clock == nil {
		return nil, fmt.Errorf("update bundle store directory and clock are required")
	}
	information, err := os.Lstat(config.Directory)
	if err != nil {
		return nil, fmt.Errorf("inspect update bundle store directory: %w", err)
	}
	if !information.IsDir() || information.Mode()&os.ModeSymlink != 0 {
		return nil, fmt.Errorf("update bundle store directory must be a regular non-symlink directory")
	}
	return &FileSystemStore{directory: filepath.Clean(config.Directory), clock: config.Clock}, nil
}

func (store *FileSystemStore) Import(ctx context.Context, command hostagentdomain.HostUpdateBundleImportCommand) (hostagentdomain.HostUpdateBundleImportReceipt, error) {
	if err := ctx.Err(); err != nil {
		return hostagentdomain.HostUpdateBundleImportReceipt{}, fmt.Errorf("update bundle import cancelled: %w", err)
	}
	source, err := safeDirectory(command.SourceDirectory)
	if err != nil {
		return hostagentdomain.HostUpdateBundleImportReceipt{}, fmt.Errorf("%w: %v", hostagentapplication.ErrHostUpdateBundleInvalid, err)
	}
	bundle, err := readBundleDeclaration(source)
	if err != nil {
		return hostagentdomain.HostUpdateBundleImportReceipt{}, fmt.Errorf("%w: %v", hostagentapplication.ErrHostUpdateBundleInvalid, err)
	}
	fingerprint, err := bundleTreeFingerprint(ctx, source)
	if err != nil {
		return hostagentdomain.HostUpdateBundleImportReceipt{}, fmt.Errorf("%w: %v", hostagentapplication.ErrHostUpdateBundleInvalid, err)
	}
	target := filepath.Join(store.directory, bundle.ID)
	state, err := store.publish(ctx, source, target, fingerprint)
	if err != nil {
		return hostagentdomain.HostUpdateBundleImportReceipt{}, err
	}
	return hostagentdomain.HostUpdateBundleImportReceipt{
		SchemaVersion:     hostagentdomain.SchemaVersion,
		State:             state,
		RequestID:         command.RequestID,
		ObservedAt:        hostagentdomain.Timestamp(store.clock.Now()),
		Bundle:            bundle,
		SourceFingerprint: fingerprint,
	}, nil
}

func (store *FileSystemStore) Read(ctx context.Context, bundleID string) (hostagentdomain.HostUpdateBundleDeclaration, error) {
	if err := ctx.Err(); err != nil {
		return hostagentdomain.HostUpdateBundleDeclaration{}, fmt.Errorf("read update bundle cancelled: %w", err)
	}
	if !hostagentdomain.ValidIdentifier(bundleID) {
		return hostagentdomain.HostUpdateBundleDeclaration{}, fmt.Errorf("%w: bundle id is invalid", hostagentapplication.ErrHostUpdateBundleInvalid)
	}
	bundleDirectory := filepath.Join(store.directory, bundleID)
	information, err := os.Lstat(bundleDirectory)
	if errors.Is(err, os.ErrNotExist) {
		return hostagentdomain.HostUpdateBundleDeclaration{}, hostagentapplication.ErrHostUpdateBundleNotFound
	}
	if err != nil {
		return hostagentdomain.HostUpdateBundleDeclaration{}, fmt.Errorf("inspect imported update bundle: %w", err)
	}
	if !information.IsDir() || information.Mode()&os.ModeSymlink != 0 {
		return hostagentdomain.HostUpdateBundleDeclaration{}, fmt.Errorf("%w: imported update bundle must be a regular non-symlink directory", hostagentapplication.ErrHostUpdateBundleInvalid)
	}
	bundle, err := readBundleDeclaration(bundleDirectory)
	if err != nil {
		return hostagentdomain.HostUpdateBundleDeclaration{}, fmt.Errorf("%w: %v", hostagentapplication.ErrHostUpdateBundleInvalid, err)
	}
	if bundle.ID != bundleID {
		return hostagentdomain.HostUpdateBundleDeclaration{}, fmt.Errorf("%w: imported directory id does not match bootstrap envelope id", hostagentapplication.ErrHostUpdateBundleInvalid)
	}
	return bundle, nil
}

func (store *FileSystemStore) publish(ctx context.Context, source string, target string, sourceFingerprint string) (string, error) {
	if target != filepath.Join(store.directory, filepath.Base(target)) {
		return "", fmt.Errorf("%w: target bundle reference is unsafe", hostagentapplication.ErrHostUpdateBundleInvalid)
	}
	if information, err := os.Lstat(target); err == nil {
		if !information.IsDir() || information.Mode()&os.ModeSymlink != 0 {
			return "", fmt.Errorf("%w: existing imported bundle is not a regular directory", hostagentapplication.ErrHostUpdateBundleConflict)
		}
		existingFingerprint, fingerprintErr := bundleTreeFingerprint(ctx, target)
		if fingerprintErr != nil {
			return "", fmt.Errorf("%w: existing imported bundle is invalid: %v", hostagentapplication.ErrHostUpdateBundleConflict, fingerprintErr)
		}
		if existingFingerprint != sourceFingerprint {
			return "", fmt.Errorf("%w: bundle id already names different immutable bytes", hostagentapplication.ErrHostUpdateBundleConflict)
		}
		return "already-imported", nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return "", fmt.Errorf("inspect imported update bundle target: %w", err)
	}
	temporary, err := os.MkdirTemp(store.directory, ".update-bundle-import-")
	if err != nil {
		return "", fmt.Errorf("create temporary update bundle directory: %w", err)
	}
	defer os.RemoveAll(temporary)
	if err := copyBundleTree(ctx, source, temporary); err != nil {
		return "", fmt.Errorf("%w: %v", hostagentapplication.ErrHostUpdateBundleInvalid, err)
	}
	persistedFingerprint, err := bundleTreeFingerprint(ctx, temporary)
	if err != nil {
		return "", fmt.Errorf("%w: copied bundle cannot be verified: %v", hostagentapplication.ErrHostUpdateBundleInvalid, err)
	}
	if persistedFingerprint != sourceFingerprint {
		return "", fmt.Errorf("%w: copied bundle fingerprint differs from selected source", hostagentapplication.ErrHostUpdateBundleInvalid)
	}
	if err := os.Rename(temporary, target); err != nil {
		if errors.Is(err, fs.ErrExist) {
			return store.publish(ctx, source, target, sourceFingerprint)
		}
		return "", fmt.Errorf("publish imported update bundle: %w", err)
	}
	return "imported", nil
}

func safeDirectory(path string) (string, error) {
	if !filepath.IsAbs(path) || strings.ContainsRune(path, '\x00') {
		return "", errors.New("sourceDirectory must be an absolute Host path")
	}
	clean := filepath.Clean(path)
	for _, component := range strings.FieldsFunc(clean, func(character rune) bool { return character == '/' || character == '\\' }) {
		if component == ".." {
			return "", errors.New("sourceDirectory must not traverse parent directories")
		}
	}
	information, err := os.Lstat(clean)
	if err != nil {
		return "", fmt.Errorf("inspect sourceDirectory: %w", err)
	}
	if !information.IsDir() || information.Mode()&os.ModeSymlink != 0 {
		return "", errors.New("sourceDirectory must be a regular non-symlink directory")
	}
	return clean, nil
}

func readBundleDeclaration(directory string) (hostagentdomain.HostUpdateBundleDeclaration, error) {
	path := filepath.Join(directory, bootstrapEnvelopeFilename)
	information, err := os.Lstat(path)
	if err != nil {
		return hostagentdomain.HostUpdateBundleDeclaration{}, fmt.Errorf("inspect bootstrap envelope: %w", err)
	}
	if !information.Mode().IsRegular() || information.Mode()&os.ModeSymlink != 0 || information.Size() > 1<<20 {
		return hostagentdomain.HostUpdateBundleDeclaration{}, errors.New("bootstrap envelope must be a regular non-symlink file no larger than 1 MiB")
	}
	encoded, err := os.ReadFile(path)
	if err != nil {
		return hostagentdomain.HostUpdateBundleDeclaration{}, fmt.Errorf("read bootstrap envelope: %w", err)
	}
	decoder := json.NewDecoder(strings.NewReader(string(encoded)))
	decoder.DisallowUnknownFields()
	var envelope hostagentdomain.UpdateBootstrapEnvelope
	if err := decoder.Decode(&envelope); err != nil {
		return hostagentdomain.HostUpdateBundleDeclaration{}, fmt.Errorf("decode bootstrap envelope: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return hostagentdomain.HostUpdateBundleDeclaration{}, errors.New("bootstrap envelope must contain exactly one document")
	}
	bundle := hostagentdomain.HostUpdateBundleDeclaration{SchemaVersion: hostagentdomain.SchemaVersion, ID: envelope.ID, State: "declared", BootstrapEnvelope: envelope}
	if issue := hostagentdomain.ValidateHostUpdateBundleDeclaration(bundle); issue != nil {
		return hostagentdomain.HostUpdateBundleDeclaration{}, errors.New(issue.Message)
	}
	return bundle, nil
}

func copyBundleTree(ctx context.Context, source string, destination string) error {
	return filepath.WalkDir(source, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if err := ctx.Err(); err != nil {
			return err
		}
		relative, err := filepath.Rel(source, path)
		if err != nil || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
			return errors.New("bundle contains an unsafe relative path")
		}
		if relative == "." {
			return nil
		}
		information, err := entry.Info()
		if err != nil {
			return err
		}
		if information.Mode()&os.ModeSymlink != 0 || (!information.IsDir() && !information.Mode().IsRegular()) {
			return fmt.Errorf("bundle contains unsupported filesystem entry %s", filepath.ToSlash(relative))
		}
		target := filepath.Join(destination, relative)
		if information.IsDir() {
			return os.Mkdir(target, 0o700)
		}
		return copyRegularFile(path, target, information.Mode().Perm())
	})
}

func copyRegularFile(source string, destination string, mode fs.FileMode) error {
	input, err := os.Open(source)
	if err != nil {
		return err
	}
	defer input.Close()
	output, err := os.OpenFile(destination, os.O_WRONLY|os.O_CREATE|os.O_EXCL, mode&0o700)
	if err != nil {
		return err
	}
	_, copyErr := io.Copy(output, input)
	syncErr := output.Sync()
	closeErr := output.Close()
	if copyErr != nil {
		return copyErr
	}
	if syncErr != nil {
		return syncErr
	}
	return closeErr
}

func bundleTreeFingerprint(ctx context.Context, directory string) (string, error) {
	entries := make([]string, 0)
	if err := filepath.WalkDir(directory, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if err := ctx.Err(); err != nil {
			return err
		}
		relative, err := filepath.Rel(directory, path)
		if err != nil {
			return err
		}
		if relative == "." {
			return nil
		}
		information, err := entry.Info()
		if err != nil {
			return err
		}
		if information.Mode()&os.ModeSymlink != 0 || (!information.IsDir() && !information.Mode().IsRegular()) {
			return fmt.Errorf("bundle contains unsupported filesystem entry %s", filepath.ToSlash(relative))
		}
		kind := "file"
		if information.IsDir() {
			kind = "directory"
		}
		entries = append(entries, kind+"\x00"+filepath.ToSlash(relative))
		return nil
	}); err != nil {
		return "", err
	}
	sort.Strings(entries)
	hash := sha256.New()
	for _, entry := range entries {
		parts := strings.SplitN(entry, "\x00", 2)
		_, _ = io.WriteString(hash, parts[0]+"\x00"+parts[1]+"\x00")
		if parts[0] != "file" {
			continue
		}
		file, err := os.Open(filepath.Join(directory, filepath.FromSlash(parts[1])))
		if err != nil {
			return "", err
		}
		_, copyErr := io.Copy(hash, file)
		closeErr := file.Close()
		if copyErr != nil {
			return "", copyErr
		}
		if closeErr != nil {
			return "", closeErr
		}
		_, _ = io.WriteString(hash, "\x00")
	}
	return hex.EncodeToString(hash.Sum(nil)), nil
}
