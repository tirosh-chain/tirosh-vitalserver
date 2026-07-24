package gueststatesqliterepository

import (
	"context"
	"path/filepath"
	"testing"
)

func TestReadGuestOperationalStateSQLiteIdentityReturnsDurableOwnerMetadata(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "guest.sqlite")
	repository, err := OpenGuestRuntimeStateSQLiteRepository(ctx, path)
	if err != nil {
		t.Fatal(err)
	}
	first, err := repository.ReadGuestOperationalStateSQLiteIdentity(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if err := repository.Close(); err != nil {
		t.Fatal(err)
	}
	repository, err = OpenGuestRuntimeStateSQLiteRepository(ctx, path)
	if err != nil {
		t.Fatal(err)
	}
	defer repository.Close()
	second, err := repository.ReadGuestOperationalStateSQLiteIdentity(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if first.DatabaseID == "" || first != second || first.SchemaVersion != 1 {
		t.Fatalf("first=%+v second=%+v", first, second)
	}
}
