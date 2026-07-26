// Package postgresqlcommandenvironment translates one explicit PostgreSQL
// URL material into the libpq environment owned by PostgreSQL command-line
// adapters. The URL is not placed in argv, where credentials would be visible
// to process inspection.
package postgresqlcommandenvironment

import (
	"fmt"
	"net/url"
	"strconv"
	"strings"
)

var queryEnvironmentNames = map[string]string{
	"application_name":     "PGAPPNAME",
	"channel_binding":      "PGCHANNELBINDING",
	"connect_timeout":      "PGCONNECT_TIMEOUT",
	"gssencmode":           "PGGSSENCMODE",
	"options":              "PGOPTIONS",
	"sslcert":              "PGSSLCERT",
	"sslcrl":               "PGSSLCRL",
	"sslcrldir":            "PGSSLCRLDIR",
	"sslkey":               "PGSSLKEY",
	"sslmode":              "PGSSLMODE",
	"sslrootcert":          "PGSSLROOTCERT",
	"target_session_attrs": "PGTARGETSESSIONATTRS",
}

var ownedEnvironmentNames = func() map[string]struct{} {
	names := map[string]struct{}{
		"PGDATABASE": {},
		"PGHOST":     {},
		"PGPASSWORD": {},
		"PGPORT":     {},
		"PGUSER":     {},
	}
	for _, name := range queryEnvironmentNames {
		names[name] = struct{}{}
	}
	return names
}()

// FromDatabaseURL returns a complete process environment with inherited libpq
// variables removed and replaced by the exact connection material in the URL.
// Unsupported query parameters fail explicitly instead of silently changing
// which database or TLS policy a backup command uses.
func FromDatabaseURL(
	baseEnvironment []string,
	databaseURL string,
) ([]string, error) {
	parsed, err := url.Parse(databaseURL)
	if err != nil ||
		(parsed.Scheme != "postgresql" && parsed.Scheme != "postgres") ||
		parsed.Hostname() == "" ||
		parsed.User == nil ||
		parsed.User.Username() == "" ||
		parsed.Fragment != "" {
		return nil, fmt.Errorf("PostgreSQL command database URL is incomplete")
	}
	databaseName := strings.TrimPrefix(parsed.EscapedPath(), "/")
	if databaseName == "" || strings.Contains(databaseName, "/") {
		return nil, fmt.Errorf("PostgreSQL command database name is invalid")
	}
	databaseName, err = url.PathUnescape(databaseName)
	if err != nil || databaseName == "" || strings.Contains(databaseName, "/") {
		return nil, fmt.Errorf("PostgreSQL command database name is invalid")
	}
	port := parsed.Port()
	if port == "" {
		port = "5432"
	}
	portNumber, err := strconv.Atoi(port)
	if err != nil || portNumber < 1 || portNumber > 65535 {
		return nil, fmt.Errorf("PostgreSQL command database port is invalid")
	}

	environment := make([]string, 0, len(baseEnvironment)+len(queryEnvironmentNames)+6)
	for _, entry := range baseEnvironment {
		name, _, found := strings.Cut(entry, "=")
		if !found {
			continue
		}
		if _, owned := ownedEnvironmentNames[name]; !owned {
			environment = append(environment, entry)
		}
	}
	environment = append(
		environment,
		"PGHOST="+parsed.Hostname(),
		"PGPORT="+port,
		"PGUSER="+parsed.User.Username(),
		"PGDATABASE="+databaseName,
	)
	if password, present := parsed.User.Password(); present {
		environment = append(environment, "PGPASSWORD="+password)
	}
	for key, values := range parsed.Query() {
		environmentName, supported := queryEnvironmentNames[key]
		if !supported {
			return nil, fmt.Errorf(
				"PostgreSQL command database URL query parameter is unsupported: %s",
				key,
			)
		}
		if len(values) != 1 || values[0] == "" {
			return nil, fmt.Errorf(
				"PostgreSQL command database URL query parameter is invalid: %s",
				key,
			)
		}
		environment = append(environment, environmentName+"="+values[0])
	}
	return environment, nil
}
