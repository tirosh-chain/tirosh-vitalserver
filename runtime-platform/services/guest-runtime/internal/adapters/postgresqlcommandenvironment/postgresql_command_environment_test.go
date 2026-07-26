package postgresqlcommandenvironment

import (
	"slices"
	"strings"
	"testing"
)

func TestFromDatabaseURLReplacesInheritedLibpqStateWithoutPuttingURLInEnvironment(
	t *testing.T,
) {
	databaseURL := "postgresql://catalog-user:secret@db.example.test:5544/vital%20server?sslmode=verify-full&connect_timeout=5"
	environment, err := FromDatabaseURL(
		[]string{
			"PATH=/usr/bin",
			"PGHOST=stale-host",
			"PGPASSWORD=stale-password",
			"PGSSLMODE=disable",
		},
		databaseURL,
	)
	if err != nil {
		t.Fatal(err)
	}
	for _, expected := range []string{
		"PATH=/usr/bin",
		"PGHOST=db.example.test",
		"PGPORT=5544",
		"PGUSER=catalog-user",
		"PGPASSWORD=secret",
		"PGDATABASE=vital server",
		"PGSSLMODE=verify-full",
		"PGCONNECT_TIMEOUT=5",
	} {
		if !slices.Contains(environment, expected) {
			t.Fatalf("environment omitted %q: %#v", expected, environment)
		}
	}
	for _, entry := range environment {
		if strings.Contains(entry, databaseURL) ||
			entry == "PGHOST=stale-host" ||
			entry == "PGPASSWORD=stale-password" ||
			entry == "PGSSLMODE=disable" {
			t.Fatalf("environment retained ambiguous connection state: %q", entry)
		}
	}
}

func TestFromDatabaseURLRejectsUnsupportedConnectionPolicy(t *testing.T) {
	if _, err := FromDatabaseURL(
		nil,
		"postgresql://catalog-user@db.example.test/vitalserver?fallback_application_name=hidden",
	); err == nil || !strings.Contains(err.Error(), "unsupported") {
		t.Fatalf("error=%v", err)
	}
}

func TestFromDatabaseURLUsesExplicitDefaultPortAndOmitsMissingPassword(
	t *testing.T,
) {
	environment, err := FromDatabaseURL(
		[]string{"PGPASSWORD=stale"},
		"postgres://catalog-user@db.example.test/vitalserver",
	)
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Contains(environment, "PGPORT=5432") {
		t.Fatalf("environment=%#v", environment)
	}
	for _, entry := range environment {
		if strings.HasPrefix(entry, "PGPASSWORD=") {
			t.Fatalf("password must be absent: %#v", environment)
		}
	}
}
