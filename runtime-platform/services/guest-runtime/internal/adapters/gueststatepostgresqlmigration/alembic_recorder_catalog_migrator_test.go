package gueststatepostgresqlmigration

import (
	"context"
	"strings"
	"testing"
)

func TestBoundedCommandOutputPreservesBoundAndReportsTruncation(t *testing.T) {
	output := &boundedCommandOutput{maximumBytes: 5}
	written, err := output.Write([]byte("123456789"))
	if err != nil {
		t.Fatal(err)
	}
	if written != 9 {
		t.Fatalf("written=%d", written)
	}
	if value := output.String(); value != "12345 [output truncated]" {
		t.Fatalf("output=%q", value)
	}
}

func TestApplyRecorderCatalogMigrationsRejectsIncompleteConfiguration(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	_, err := ApplyRecorderCatalogMigrations(
		ctx,
		RecorderCatalogMigrationConfiguration{},
	)
	if err == nil || !strings.Contains(err.Error(), "configuration is incomplete") {
		t.Fatalf("error=%v", err)
	}
}
