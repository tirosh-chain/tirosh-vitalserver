// Package migrations exposes the exact Alembic migration tree compiled into
// the Guest Runtime binary. Python migration sources remain canonical; the
// Guest bootstrap does not fetch or reconstruct schema state at runtime.
package migrations

import (
	"embed"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
)

// migrationSources contains only release migration inputs. Test caches and
// local Python artifacts are deliberately not part of the product binary.
//
//go:embed alembic.ini env.py script.py.mako versions/*.py
var migrationSources embed.FS

// Materialize writes one private, exact migration tree below destination.
// The caller owns destination and must supply an empty directory.
func Materialize(destination string) error {
	if destination == "" {
		return fmt.Errorf("Recorder Catalog migration destination is required")
	}
	entries, err := os.ReadDir(destination)
	if err != nil {
		return fmt.Errorf("read Recorder Catalog migration destination: %w", err)
	}
	if len(entries) != 0 {
		return fmt.Errorf("Recorder Catalog migration destination must be empty")
	}
	return fs.WalkDir(migrationSources, ".", func(sourcePath string, entry fs.DirEntry, walkError error) error {
		if walkError != nil {
			return walkError
		}
		if sourcePath == "." {
			return nil
		}
		destinationPath := filepath.Join(destination, filepath.FromSlash(sourcePath))
		if entry.IsDir() {
			if err := os.Mkdir(destinationPath, 0o700); err != nil {
				return fmt.Errorf("create embedded Recorder Catalog migration directory: %w", err)
			}
			return nil
		}
		contents, err := migrationSources.ReadFile(sourcePath)
		if err != nil {
			return fmt.Errorf("read embedded Recorder Catalog migration source: %w", err)
		}
		if err := os.WriteFile(destinationPath, contents, 0o600); err != nil {
			return fmt.Errorf("write embedded Recorder Catalog migration source: %w", err)
		}
		return nil
	})
}
