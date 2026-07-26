// Package platformctlcommand parses explicit platformctl invocations into
// published Control API requests. It has no Host or Guest state.
package platformctlcommand

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"regexp"
	"strconv"
	"strings"
)

var identifierPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$`)
var telemetryAttributeKeyPattern = regexp.MustCompile(`^[a-z][a-z0-9_.-]*$`)

// Invocation is one selected public control route and, for a command, its
// caller-supplied JSON body. It is intentionally not a domain command model.
type Invocation struct {
	ControlEndpoint            string
	LocalControlDescriptorPath string
	Method                     string
	Route                      string
	Body                       []byte
	// ReadsPasswordFromStandardInput is an explicit local transport request,
	// not part of the public JSON contract. Only the CLI entrypoint consumes
	// it immediately before sending the one named credential-material command.
	// Keeping the password out of argv and this parser's output prevents it
	// from entering shell history, process listings, or parser diagnostics.
	ReadsPasswordFromStandardInput bool
}

// Parse requires the operator to supply a control endpoint and maps only
// named, published routes. It never constructs an endpoint identity,
// resource revision, or request ID from another response.
func Parse(arguments []string) (Invocation, error) {
	if len(arguments) < 3 || arguments[1] == "" {
		return Invocation{}, errors.New("usage requires --local-control-descriptor <absolute-path> or --control-endpoint <http://127.0.0.1:port> before a command")
	}
	invocation := Invocation{}
	switch arguments[0] {
	case "--control-endpoint":
		invocation.ControlEndpoint = arguments[1]
	case "--local-control-descriptor":
		invocation.LocalControlDescriptorPath = arguments[1]
	default:
		return Invocation{}, errors.New("usage requires --local-control-descriptor <absolute-path> or --control-endpoint <http://127.0.0.1:port> before a command")
	}
	command := arguments[2:]
	if len(command) == 1 {
		switch command[0] {
		case "installation":
			return read(invocation, "/v1/platform/installation"), nil
		case "guest-runtime-control-endpoint":
			return read(invocation, "/v1/platform/guest-runtime-control-endpoint"), nil
		case "host-clock-quality":
			return read(invocation, "/v1/platform/time/clock-quality"), nil
		}
	}
	if len(command) >= 2 && command[0] == "update" {
		return parseUpdateCommand(invocation, command[1:])
	}
	if len(command) >= 2 && command[0] == "lab" {
		return parseLabCommand(invocation, command[1:])
	}
	if len(command) >= 2 && command[0] == "archive" {
		return parseArchiveCommand(invocation, command[1:])
	}
	if len(command) >= 2 && command[0] == "external-upstream" {
		return parseExternalUpstreamCommand(invocation, command[1:])
	}
	if len(command) >= 2 && command[0] == "topology" {
		return parseTopologyCommand(invocation, command[1:])
	}
	if len(command) >= 2 && command[0] == "time" {
		return parseTimeAuthorityCommand(invocation, command[1:])
	}
	if len(command) >= 2 && command[0] == "telemetry" {
		return parseTelemetryPipelineCommand(invocation, command[1:])
	}
	if len(command) >= 2 && command[0] == "recorder" {
		return parseRecorderCommand(invocation, command[1:])
	}
	if len(command) >= 2 && command[0] == "operational-state" {
		return parseOperationalStateCommand(invocation, command[1:])
	}
	if len(command) == 2 && command[0] == "runtime" {
		switch command[1] {
		case "readiness":
			return read(invocation, "/v1/runtime/readiness"), nil
		case "topology":
			return read(invocation, "/v1/runtime/topology"), nil
		case "capabilities":
			return read(invocation, "/v1/runtime/capabilities"), nil
		case "operational-state-identity":
			return read(invocation, "/v1/runtime/operational-state/identity"), nil
		case "lab-sessions":
			return read(invocation, "/v1/runtime/lab/sessions"), nil
		case "lab-beds":
			return read(invocation, "/v1/runtime/lab/beds"), nil
		case "lab-recorders":
			return read(invocation, "/v1/runtime/lab/recorders"), nil
		case "archive-export-provider":
			return read(invocation, "/v1/runtime/archive/export-provider"), nil
		case "archive-credential-material":
			return read(invocation, "/v1/runtime/archive/credential-material"), nil
		case "external-upstreams":
			return read(invocation, "/v1/runtime/external-upstreams"), nil
		case "outbound-relays":
			return read(invocation, "/v1/runtime/relay-targets"), nil
		case "guest-clock-quality":
			return read(invocation, "/v1/time/clock-quality"), nil
		}
	}
	if len(command) >= 3 && command[0] == "operation" {
		flags, err := parseNamedFlags(command[2:])
		if err != nil {
			return Invocation{}, err
		}
		operationID, err := requiredFlag(flags, "--operation-id")
		if err != nil {
			return Invocation{}, err
		}
		switch command[1] {
		case "host":
			return read(invocation, "/v1/platform/operations/"+operationID), nil
		case "runtime":
			return read(invocation, "/v1/runtime/operations/"+operationID), nil
		default:
			return Invocation{}, errors.New("operation scope must be host or runtime")
		}
	}
	if len(command) >= 3 && command[0] == "guest" {
		action := command[1]
		if action != "start" && action != "stop" && action != "reboot" {
			return Invocation{}, errors.New("guest action must be start, stop, or reboot")
		}
		flags, err := parseNamedFlags(command[2:])
		if err != nil {
			return Invocation{}, err
		}
		requestID, err := requiredFlag(flags, "--request-id")
		if err != nil {
			return Invocation{}, err
		}
		endpointID, err := requiredFlag(flags, "--guest-runtime-control-endpoint-id")
		if err != nil {
			return Invocation{}, err
		}
		revisionText, err := requiredFlag(flags, "--expected-resource-revision")
		if err != nil {
			return Invocation{}, err
		}
		revision, err := strconv.Atoi(revisionText)
		if err != nil || revision < 0 {
			return Invocation{}, errors.New("--expected-resource-revision must be a non-negative integer")
		}
		body, err := json.Marshal(map[string]any{
			"schemaVersion":                 "v1",
			"requestId":                     requestID,
			"guestRuntimeControlEndpointId": endpointID,
			"expectedResourceRevision":      revision,
			"action":                        action,
		})
		if err != nil {
			return Invocation{}, fmt.Errorf("encode guest lifecycle command: %w", err)
		}
		invocation.Method = http.MethodPost
		invocation.Route = "/v1/platform/guest:" + action
		invocation.Body = body
		return invocation, nil
	}
	return Invocation{}, errors.New("unknown command; run platformctl help")
}

func parseOperationalStateCommand(
	invocation Invocation,
	command []string,
) (Invocation, error) {
	if len(command) < 1 {
		return Invocation{}, errors.New(
			"operational-state command must be backup, restore, or read",
		)
	}
	flags, err := parseNamedFlags(command[1:])
	if err != nil {
		return Invocation{}, err
	}
	if command[0] == "read" {
		if err := requireOnlyFlags(flags, "--operation-id"); err != nil {
			return Invocation{}, err
		}
		operationID, err := requiredIdentifierFlag(flags, "--operation-id")
		if err != nil {
			return Invocation{}, err
		}
		return read(
			invocation,
			"/v1/runtime/operational-state/operations/"+operationID,
		), nil
	}
	requestID, err := requiredIdentifierFlag(flags, "--request-id")
	if err != nil {
		return Invocation{}, err
	}
	operationID, err := requiredIdentifierFlag(flags, "--operation-id")
	if err != nil {
		return Invocation{}, err
	}
	requestedAt, err := requiredBoundedTextFlag(flags, "--requested-at", 64)
	if err != nil {
		return Invocation{}, err
	}
	body := map[string]any{
		"schemaVersion": "v1",
		"requestId":     requestID,
		"operationId":   operationID,
		"requestedAt":   requestedAt,
	}
	var route string
	switch command[0] {
	case "backup":
		if err := requireOnlyFlags(
			flags,
			"--request-id",
			"--operation-id",
			"--destination-resource-type",
			"--destination-resource-id",
			"--requested-at",
		); err != nil {
			return Invocation{}, err
		}
		resourceType, err := requiredIdentifierFlag(
			flags,
			"--destination-resource-type",
		)
		if err != nil {
			return Invocation{}, err
		}
		resourceID, err := requiredIdentifierFlag(
			flags,
			"--destination-resource-id",
		)
		if err != nil {
			return Invocation{}, err
		}
		body["destinationReference"] = map[string]string{
			"resourceType": resourceType,
			"resourceId":   resourceID,
		}
		route = "/v1/runtime/operational-state/backups"
	case "restore":
		if err := requireOnlyFlags(
			flags,
			"--request-id",
			"--operation-id",
			"--manifest-resource-type",
			"--manifest-resource-id",
			"--manifest-sha256",
			"--target-resource-type",
			"--target-resource-id",
			"--requested-at",
		); err != nil {
			return Invocation{}, err
		}
		manifestType, err := requiredIdentifierFlag(
			flags,
			"--manifest-resource-type",
		)
		if err != nil {
			return Invocation{}, err
		}
		manifestID, err := requiredIdentifierFlag(
			flags,
			"--manifest-resource-id",
		)
		if err != nil {
			return Invocation{}, err
		}
		manifestSHA256, err := requiredFlag(flags, "--manifest-sha256")
		if err != nil ||
			len(manifestSHA256) != 64 ||
			strings.Trim(manifestSHA256, "0123456789abcdef") != "" {
			return Invocation{}, errors.New(
				"--manifest-sha256 must be 64 lowercase hexadecimal characters",
			)
		}
		targetType, err := requiredIdentifierFlag(
			flags,
			"--target-resource-type",
		)
		if err != nil {
			return Invocation{}, err
		}
		targetID, err := requiredIdentifierFlag(
			flags,
			"--target-resource-id",
		)
		if err != nil {
			return Invocation{}, err
		}
		body["manifestReference"] = map[string]string{
			"resourceType": manifestType,
			"resourceId":   manifestID,
		}
		body["manifestSha256"] = manifestSHA256
		body["targetReference"] = map[string]string{
			"resourceType": targetType,
			"resourceId":   targetID,
		}
		route = "/v1/runtime/operational-state/restores"
	default:
		return Invocation{}, errors.New(
			"operational-state command must be backup, restore, or read",
		)
	}
	encoded, err := json.Marshal(body)
	if err != nil {
		return Invocation{}, fmt.Errorf(
			"encode operational-state command: %w",
			err,
		)
	}
	invocation.Method = http.MethodPost
	invocation.Route = route
	invocation.Body = encoded
	return invocation, nil
}

func parseRecorderCommand(invocation Invocation, command []string) (Invocation, error) {
	if len(command) >= 1 && command[0] == "artifacts" {
		flags, err := parseNamedFlags(command[1:])
		if err != nil {
			return Invocation{}, err
		}
		if err := requireOnlyFlags(flags, "--recorder-id", "--limit"); err != nil {
			return Invocation{}, err
		}
		recorderID, err := requiredIdentifierFlag(flags, "--recorder-id")
		if err != nil {
			return Invocation{}, err
		}
		limit, err := requiredPositiveInteger(flags, "--limit")
		if err != nil || limit > 100 {
			return Invocation{}, errors.New(
				"--limit must be an integer from 1 through 100",
			)
		}
		return read(
			invocation,
			"/v1/runtime/recorders/"+recorderID+
				"/artifacts?limit="+strconv.Itoa(limit),
		), nil
	}
	if len(command) < 1 || command[0] != "assignment" {
		return Invocation{}, errors.New(
			"recorder command must be artifacts or assignment",
		)
	}
	flags, err := parseNamedFlags(command[1:])
	if err != nil {
		return Invocation{}, err
	}
	if err := requireOnlyFlags(
		flags,
		"--request-id",
		"--evidence-id",
		"--recorder-id",
		"--bed-name",
		"--effective-from",
		"--effective-until",
		"--observed-at",
		"--source-reference-kind",
		"--source-reference-id",
	); err != nil {
		return Invocation{}, err
	}
	requestID, err := requiredIdentifierFlag(flags, "--request-id")
	if err != nil {
		return Invocation{}, err
	}
	evidenceID, err := requiredIdentifierFlag(flags, "--evidence-id")
	if err != nil {
		return Invocation{}, err
	}
	recorderID, err := requiredIdentifierFlag(flags, "--recorder-id")
	if err != nil {
		return Invocation{}, err
	}
	bedName, err := requiredBoundedTextFlag(flags, "--bed-name", 255)
	if err != nil {
		return Invocation{}, err
	}
	effectiveFrom, err := requiredBoundedTextFlag(flags, "--effective-from", 64)
	if err != nil {
		return Invocation{}, err
	}
	observedAt, err := requiredBoundedTextFlag(flags, "--observed-at", 64)
	if err != nil {
		return Invocation{}, err
	}
	sourceReferenceKind, err := requiredIdentifierFlag(flags, "--source-reference-kind")
	if err != nil {
		return Invocation{}, err
	}
	sourceReferenceID, err := requiredIdentifierFlag(flags, "--source-reference-id")
	if err != nil {
		return Invocation{}, err
	}
	body := map[string]any{
		"schemaVersion": "v1",
		"requestId":     requestID,
		"evidenceId":    evidenceID,
		"recorderId":    recorderID,
		"bedName":       bedName,
		"effectiveFrom": effectiveFrom,
		"observedAt":    observedAt,
		"sourceKind":    "administrator",
		"sourceReference": map[string]any{
			"kind": sourceReferenceKind,
			"id":   sourceReferenceID,
		},
	}
	if effectiveUntil, exists := flags["--effective-until"]; exists {
		if len(effectiveUntil) > 64 {
			return Invocation{}, errors.New("--effective-until must contain at most 64 bytes")
		}
		body["effectiveUntil"] = effectiveUntil
	}
	encoded, err := json.Marshal(body)
	if err != nil {
		return Invocation{}, fmt.Errorf("encode Recorder assignment command: %w", err)
	}
	invocation.Method = http.MethodPost
	invocation.Route = "/v1/runtime/recorder-assignments"
	invocation.Body = encoded
	return invocation, nil
}

// parseUpdateCommand is intentionally a small named mapping, not a generic
// JSON/file passthrough.  The Host imports the selected directory and reads
// its stored C25 declaration before it enters C27, so platformctl never
// authors a bootstrap envelope or an arbitrary Host control path.
func parseUpdateCommand(invocation Invocation, command []string) (Invocation, error) {
	if len(command) >= 1 && command[0] == "import" {
		flags, err := parseNamedFlags(command[1:])
		if err != nil {
			return Invocation{}, err
		}
		requestID, err := requiredFlag(flags, "--request-id")
		if err != nil {
			return Invocation{}, err
		}
		sourceDirectory, err := requiredFlag(flags, "--source-directory")
		if err != nil {
			return Invocation{}, err
		}
		body, err := json.Marshal(map[string]any{"schemaVersion": "v1", "requestId": requestID, "sourceDirectory": sourceDirectory})
		if err != nil {
			return Invocation{}, fmt.Errorf("encode update bundle import command: %w", err)
		}
		invocation.Method = http.MethodPost
		invocation.Route = "/v1/platform/update-bundles:import"
		invocation.Body = body
		return invocation, nil
	}
	if len(command) >= 1 && command[0] == "read" {
		flags, err := parseNamedFlags(command[1:])
		if err != nil {
			return Invocation{}, err
		}
		bundleID, err := requiredFlag(flags, "--bundle-id")
		if err != nil {
			return Invocation{}, err
		}
		if !identifierPattern.MatchString(bundleID) {
			return Invocation{}, errors.New("--bundle-id must be a published identifier")
		}
		return read(invocation, "/v1/platform/update-bundles/"+bundleID), nil
	}
	if len(command) >= 1 && command[0] == "apply" {
		flags, err := parseNamedFlags(command[1:])
		if err != nil {
			return Invocation{}, err
		}
		requestID, err := requiredFlag(flags, "--request-id")
		if err != nil {
			return Invocation{}, err
		}
		installationID, err := requiredFlag(flags, "--installation-id")
		if err != nil {
			return Invocation{}, err
		}
		revisionText, err := requiredFlag(flags, "--expected-installation-revision")
		if err != nil {
			return Invocation{}, err
		}
		revision, err := strconv.Atoi(revisionText)
		if err != nil || revision < 1 {
			return Invocation{}, errors.New("--expected-installation-revision must be a positive integer")
		}
		bundleID, err := requiredFlag(flags, "--bundle-id")
		if err != nil {
			return Invocation{}, err
		}
		if !identifierPattern.MatchString(bundleID) {
			return Invocation{}, errors.New("--bundle-id must be a published identifier")
		}
		body, err := json.Marshal(map[string]any{
			"schemaVersion": "v1", "requestId": requestID, "installationId": installationID,
			"expectedInstallationRevision": revision, "bundleReferenceId": bundleID,
		})
		if err != nil {
			return Invocation{}, fmt.Errorf("encode imported update bundle apply command: %w", err)
		}
		invocation.Method = http.MethodPost
		invocation.Route = "/v1/platform/update-bundles/" + bundleID + ":apply"
		invocation.Body = body
		return invocation, nil
	}
	return Invocation{}, errors.New("update command must be import, read, or apply")
}

// parseLabCommand exposes the two published Lab command shapes only. It does
// not read a SQLite store, choose a scenario, calculate a resource revision,
// or send an arbitrary Guest Runtime body. The caller obtains current resource
// identity and revision through the named Lab reads before acting.
func parseLabCommand(invocation Invocation, command []string) (Invocation, error) {
	if len(command) >= 1 && command[0] == "create" {
		flags, err := parseNamedFlags(command[1:])
		if err != nil {
			return Invocation{}, err
		}
		if err := requireOnlyFlags(flags, "--request-id", "--session-id", "--name", "--scenario", "--recorder-count"); err != nil {
			return Invocation{}, err
		}
		requestID, err := requiredIdentifierFlag(flags, "--request-id")
		if err != nil {
			return Invocation{}, err
		}
		sessionID, err := requiredIdentifierFlag(flags, "--session-id")
		if err != nil {
			return Invocation{}, err
		}
		name, err := requiredBoundedTextFlag(flags, "--name", 128)
		if err != nil {
			return Invocation{}, err
		}
		scenario, err := requiredBoundedTextFlag(flags, "--scenario", 128)
		if err != nil {
			return Invocation{}, err
		}
		recorderCountText, err := requiredFlag(flags, "--recorder-count")
		if err != nil {
			return Invocation{}, err
		}
		recorderCount, err := strconv.Atoi(recorderCountText)
		if err != nil || recorderCount < 1 || recorderCount > 64 {
			return Invocation{}, errors.New("--recorder-count must be an integer from 1 through 64")
		}
		body, err := json.Marshal(map[string]any{
			"schemaVersion": "v1", "requestId": requestID, "sessionId": sessionID, "expectedSessionRevision": 0,
			"name": name, "scenario": scenario, "recorderCount": recorderCount,
		})
		if err != nil {
			return Invocation{}, fmt.Errorf("encode Lab session create command: %w", err)
		}
		invocation.Method = http.MethodPost
		invocation.Route = "/v1/runtime/lab/sessions"
		invocation.Body = body
		return invocation, nil
	}
	if len(command) >= 1 && command[0] == "resource" {
		flags, err := parseNamedFlags(command[1:])
		if err != nil {
			return Invocation{}, err
		}
		if err := requireOnlyFlags(flags, "--request-id", "--resource-type", "--resource-id", "--expected-resource-revision", "--action", "--cascade"); err != nil {
			return Invocation{}, err
		}
		requestID, err := requiredIdentifierFlag(flags, "--request-id")
		if err != nil {
			return Invocation{}, err
		}
		resourceType, err := requiredFlag(flags, "--resource-type")
		if err != nil {
			return Invocation{}, err
		}
		resourceID, err := requiredIdentifierFlag(flags, "--resource-id")
		if err != nil {
			return Invocation{}, err
		}
		revisionText, err := requiredFlag(flags, "--expected-resource-revision")
		if err != nil {
			return Invocation{}, err
		}
		revision, err := strconv.Atoi(revisionText)
		if err != nil || revision < 1 {
			return Invocation{}, errors.New("--expected-resource-revision must be a positive integer")
		}
		action, err := requiredFlag(flags, "--action")
		if err != nil {
			return Invocation{}, err
		}
		cascade := flags["--cascade"]
		if err := validateLabResourceCommand(resourceType, action, cascade); err != nil {
			return Invocation{}, err
		}
		body := map[string]any{
			"schemaVersion": "v1", "requestId": requestID, "resourceType": resourceType, "resourceId": resourceID,
			"expectedResourceRevision": revision, "action": action,
		}
		if cascade != "" {
			body["cascade"] = cascade
		}
		encoded, err := json.Marshal(body)
		if err != nil {
			return Invocation{}, fmt.Errorf("encode Lab resource command: %w", err)
		}
		invocation.Method = http.MethodPost
		invocation.Route = "/v1/runtime/lab/resources:command"
		invocation.Body = encoded
		return invocation, nil
	}
	return Invocation{}, errors.New("lab command must be create or resource")
}

// parseArchiveCommand exposes the two named Archive operations that the CLI
// can perform. Artifact export accepts only IDs/revisions from the Lab and
// Archive owners. Credential provisioning is distinct because its password
// never appears in argv: the entrypoint reads it from stdin immediately before
// it sends the selected command.
func parseArchiveCommand(invocation Invocation, command []string) (Invocation, error) {
	if len(command) == 1 && command[0] == "credential-material" {
		return read(invocation, "/v1/runtime/archive/credential-material"), nil
	}
	if len(command) >= 1 && command[0] == "credential-material" {
		return parseArchiveCredentialMaterialProvisionCommand(invocation, command[1:])
	}
	if len(command) >= 1 && command[0] == "artifact" {
		flags, err := parseNamedFlags(command[1:])
		if err != nil {
			return Invocation{}, err
		}
		if err := requireOnlyFlags(flags, "--artifact-id"); err != nil {
			return Invocation{}, err
		}
		artifactID, err := requiredIdentifierFlag(flags, "--artifact-id")
		if err != nil {
			return Invocation{}, err
		}
		return read(invocation, "/v1/runtime/artifacts/"+artifactID), nil
	}
	if len(command) == 0 || command[0] != "export" {
		return Invocation{}, errors.New(
			"archive command must be artifact, export, or credential-material",
		)
	}
	flags, err := parseNamedFlags(command[1:])
	if err != nil {
		return Invocation{}, err
	}
	if err := requireOnlyFlags(flags,
		"--request-id", "--virtual-recorder-id", "--expected-resource-revision",
		"--cold-path-finalization-receipt-id", "--provider-kind", "--provider-id", "--provider-capability-revision",
	); err != nil {
		return Invocation{}, err
	}
	requestID, err := requiredIdentifierFlag(flags, "--request-id")
	if err != nil {
		return Invocation{}, err
	}
	virtualRecorderID, err := requiredIdentifierFlag(flags, "--virtual-recorder-id")
	if err != nil {
		return Invocation{}, err
	}
	revision, err := requiredPositiveInteger(flags, "--expected-resource-revision")
	if err != nil {
		return Invocation{}, errors.New("--expected-resource-revision must be a positive integer")
	}
	finalizationReceiptID, err := requiredIdentifierFlag(flags, "--cold-path-finalization-receipt-id")
	if err != nil {
		return Invocation{}, err
	}
	provider, err := providerReferenceFromFlags(flags)
	if err != nil {
		return Invocation{}, err
	}
	body, err := json.Marshal(map[string]any{
		"schemaVersion": "v1", "requestId": requestID, "virtualRecorderId": virtualRecorderID,
		"expectedResourceRevision": revision,
		"source":                   map[string]any{"kind": "recorder-gateway-cold-path", "coldPathFinalizationReceiptId": finalizationReceiptID},
		"provider":                 provider,
	})
	if err != nil {
		return Invocation{}, fmt.Errorf("encode artifact export command: %w", err)
	}
	invocation.Method = http.MethodPost
	invocation.Route = "/v1/runtime/archive/exports"
	invocation.Body = body
	return invocation, nil
}

// parseArchiveCredentialMaterialProvisionCommand keeps the secret transport
// separate from the public body. The parser requires the literal stdin grant
// and publishes an incomplete body only to the CLI entrypoint; that entrypoint
// alone reads one bounded password line and attaches it before the request is
// sent. No caller can pass a password option or a password file path.
func parseArchiveCredentialMaterialProvisionCommand(invocation Invocation, command []string) (Invocation, error) {
	if len(command) == 0 || command[0] != "provision" {
		return Invocation{}, errors.New("archive credential-material command must be provision")
	}
	flags, err := parseNamedFlags(command[1:])
	if err != nil {
		return Invocation{}, err
	}
	if err := requireOnlyFlags(flags, "--credential-kind", "--credential-id", "--user-id", "--password-stdin"); err != nil {
		return Invocation{}, err
	}
	credentialKind, err := requiredIdentifierFlag(flags, "--credential-kind")
	if err != nil {
		return Invocation{}, err
	}
	credentialID, err := requiredIdentifierFlag(flags, "--credential-id")
	if err != nil {
		return Invocation{}, err
	}
	userID, err := requiredBoundedSecretInputFlag(flags, "--user-id", 1024)
	if err != nil {
		return Invocation{}, err
	}
	passwordStdin, err := requiredFlag(flags, "--password-stdin")
	if err != nil {
		return Invocation{}, err
	}
	if passwordStdin != "true" {
		return Invocation{}, errors.New("--password-stdin must be true")
	}
	body, err := json.Marshal(map[string]any{
		"schemaVersion":       "v1",
		"credentialReference": map[string]string{"kind": credentialKind, "id": credentialID},
		"userId":              userID,
	})
	if err != nil {
		return Invocation{}, fmt.Errorf("encode archive credential-material provisioning command: %w", err)
	}
	invocation.Method = http.MethodPost
	invocation.Route = "/v1/runtime/archive/credential-material"
	invocation.Body = body
	invocation.ReadsPasswordFromStandardInput = true
	return invocation, nil
}

// parseTimeAuthorityCommand exposes an NTP authority by owner-scoped source
// identity. It intentionally has no NTP host, port, credential, or raw JSON
// option: those values belong to the selected Host/Guest deployment adapter.
func parseTimeAuthorityCommand(invocation Invocation, command []string) (Invocation, error) {
	if len(command) == 0 || command[0] != "apply" {
		return Invocation{}, errors.New("time command must be apply")
	}
	flags, err := parseNamedFlags(command[1:])
	if err != nil {
		return Invocation{}, err
	}
	if err := requireOnlyFlags(flags,
		"--scope", "--request-id", "--authority-id", "--expected-resource-revision",
		"--node-kind", "--node-id", "--profile", "--source-profile", "--source-id",
	); err != nil {
		return Invocation{}, err
	}
	scope, err := requiredOperationalScope(flags)
	if err != nil {
		return Invocation{}, err
	}
	requestID, err := requiredIdentifierFlag(flags, "--request-id")
	if err != nil {
		return Invocation{}, err
	}
	authorityID, err := requiredIdentifierFlag(flags, "--authority-id")
	if err != nil {
		return Invocation{}, err
	}
	revision, err := requiredNonNegativeRevision(flags, "--expected-resource-revision")
	if err != nil {
		return Invocation{}, err
	}
	nodeKind, err := requiredIdentifierFlag(flags, "--node-kind")
	if err != nil {
		return Invocation{}, err
	}
	nodeID, err := requiredIdentifierFlag(flags, "--node-id")
	if err != nil {
		return Invocation{}, err
	}
	profile, err := requiredIdentifierFlag(flags, "--profile")
	if err != nil {
		return Invocation{}, err
	}
	sourceProfile, err := requiredIdentifierFlag(flags, "--source-profile")
	if err != nil {
		return Invocation{}, err
	}
	sourceID, err := requiredIdentifierFlag(flags, "--source-id")
	if err != nil {
		return Invocation{}, err
	}
	body, err := json.Marshal(map[string]any{
		"schemaVersion": "v1", "requestId": requestID, "authorityId": authorityID,
		"expectedResourceRevision": revision, "node": map[string]any{"kind": nodeKind, "id": nodeID},
		"spec": map[string]any{"profile": profile, "source": map[string]any{"profile": sourceProfile, "sourceId": sourceID}},
	})
	if err != nil {
		return Invocation{}, fmt.Errorf("encode time authority command: %w", err)
	}
	invocation.Method = http.MethodPost
	if scope == "host" {
		invocation.Route = "/v1/platform/time/authorities"
	} else {
		invocation.Route = "/v1/time/authorities"
	}
	invocation.Body = body
	return invocation, nil
}

// parseTelemetryPipelineCommand carries the stable OTLP signal set and a
// bounded redaction policy. Collector endpoints and credentials stay with the
// owner-published collector reference/deployment, never platformctl flags.
func parseTelemetryPipelineCommand(invocation Invocation, command []string) (Invocation, error) {
	if len(command) == 0 || command[0] != "apply" {
		return Invocation{}, errors.New("telemetry command must be apply")
	}
	flags, err := parseNamedFlags(command[1:])
	if err != nil {
		return Invocation{}, err
	}
	if err := requireOnlyFlags(flags,
		"--scope", "--request-id", "--pipeline-id", "--expected-resource-revision",
		"--node-kind", "--node-id", "--collector-resource-type", "--collector-resource-id",
		"--allowed-attribute-keys", "--max-attributes", "--max-value-length", "--max-distinct-values-per-key",
	); err != nil {
		return Invocation{}, err
	}
	scope, err := requiredOperationalScope(flags)
	if err != nil {
		return Invocation{}, err
	}
	requestID, err := requiredIdentifierFlag(flags, "--request-id")
	if err != nil {
		return Invocation{}, err
	}
	pipelineID, err := requiredIdentifierFlag(flags, "--pipeline-id")
	if err != nil {
		return Invocation{}, err
	}
	revision, err := requiredNonNegativeRevision(flags, "--expected-resource-revision")
	if err != nil {
		return Invocation{}, err
	}
	nodeKind, err := requiredIdentifierFlag(flags, "--node-kind")
	if err != nil {
		return Invocation{}, err
	}
	nodeID, err := requiredIdentifierFlag(flags, "--node-id")
	if err != nil {
		return Invocation{}, err
	}
	collectorType, err := requiredIdentifierFlag(flags, "--collector-resource-type")
	if err != nil {
		return Invocation{}, err
	}
	collectorID, err := requiredIdentifierFlag(flags, "--collector-resource-id")
	if err != nil {
		return Invocation{}, err
	}
	allowedKeysText, err := requiredFlag(flags, "--allowed-attribute-keys")
	if err != nil {
		return Invocation{}, err
	}
	allowedKeys, err := telemetryAttributeKeys(allowedKeysText)
	if err != nil {
		return Invocation{}, err
	}
	maxAttributes, err := requiredBoundedPositiveInteger(flags, "--max-attributes", 32)
	if err != nil {
		return Invocation{}, err
	}
	maxValueLength, err := requiredBoundedPositiveInteger(flags, "--max-value-length", 256)
	if err != nil {
		return Invocation{}, err
	}
	maxDistinctValuesPerKey, err := requiredBoundedPositiveInteger(flags, "--max-distinct-values-per-key", 100)
	if err != nil {
		return Invocation{}, err
	}
	body, err := json.Marshal(map[string]any{
		"schemaVersion": "v1", "requestId": requestID, "pipelineId": pipelineID,
		"expectedResourceRevision": revision, "node": map[string]any{"kind": nodeKind, "id": nodeID},
		"spec": map[string]any{
			"protocol": "otlp-http", "collectorReference": map[string]any{"resourceType": collectorType, "resourceId": collectorID},
			"signalKinds": []string{"logs", "metrics", "traces"},
			"redaction":   map[string]any{"allowedAttributeKeys": allowedKeys, "maxAttributes": maxAttributes, "maxValueLength": maxValueLength, "maxDistinctValuesPerKey": maxDistinctValuesPerKey},
		},
	})
	if err != nil {
		return Invocation{}, fmt.Errorf("encode telemetry pipeline command: %w", err)
	}
	invocation.Method = http.MethodPost
	if scope == "host" {
		invocation.Route = "/v1/platform/telemetry/pipelines"
	} else {
		invocation.Route = "/v1/runtime/telemetry/pipelines"
	}
	invocation.Body = body
	return invocation, nil
}

func read(invocation Invocation, route string) Invocation {
	invocation.Method = http.MethodGet
	invocation.Route = route
	return invocation
}

func parseNamedFlags(arguments []string) (map[string]string, error) {
	if len(arguments)%2 != 0 {
		return nil, errors.New("command options must be --name value pairs")
	}
	flags := make(map[string]string, len(arguments)/2)
	for index := 0; index < len(arguments); index += 2 {
		name, value := arguments[index], arguments[index+1]
		if len(name) < 3 || name[:2] != "--" || value == "" {
			return nil, errors.New("command options must be non-empty --name value pairs")
		}
		if _, exists := flags[name]; exists {
			return nil, fmt.Errorf("command option %s is repeated", name)
		}
		flags[name] = value
	}
	return flags, nil
}

func requiredFlag(flags map[string]string, name string) (string, error) {
	value, exists := flags[name]
	if !exists {
		return "", fmt.Errorf("%s is required", name)
	}
	return value, nil
}

func requiredIdentifierFlag(flags map[string]string, name string) (string, error) {
	value, err := requiredFlag(flags, name)
	if err != nil {
		return "", err
	}
	if !identifierPattern.MatchString(value) {
		return "", fmt.Errorf("%s must be a published identifier", name)
	}
	return value, nil
}

func requiredBoundedTextFlag(flags map[string]string, name string, maximumLength int) (string, error) {
	value, err := requiredFlag(flags, name)
	if err != nil {
		return "", err
	}
	if len(value) > maximumLength {
		return "", fmt.Errorf("%s must contain at most %d bytes", name, maximumLength)
	}
	return value, nil
}

func requiredBoundedSecretInputFlag(flags map[string]string, name string, maximumLength int) (string, error) {
	value, err := requiredFlag(flags, name)
	if err != nil {
		return "", err
	}
	if len(value) > maximumLength || strings.ContainsAny(value, "\x00\r\n") {
		return "", fmt.Errorf("%s must be a bounded non-empty single-line string", name)
	}
	return value, nil
}

func requiredOperationalScope(flags map[string]string) (string, error) {
	scope, err := requiredFlag(flags, "--scope")
	if err != nil {
		return "", err
	}
	if scope != "host" && scope != "guest" {
		return "", errors.New("--scope must be host or guest")
	}
	return scope, nil
}

func requiredBoundedPositiveInteger(flags map[string]string, name string, maximum int) (int, error) {
	value, err := requiredFlag(flags, name)
	if err != nil {
		return 0, err
	}
	integer, err := strconv.Atoi(value)
	if err != nil || integer < 1 || integer > maximum {
		return 0, fmt.Errorf("%s must be an integer from 1 through %d", name, maximum)
	}
	return integer, nil
}

func requiredPositiveInteger(flags map[string]string, name string) (int, error) {
	value, err := requiredFlag(flags, name)
	if err != nil {
		return 0, err
	}
	integer, err := strconv.Atoi(value)
	if err != nil || integer < 1 {
		return 0, fmt.Errorf("%s must be a positive integer", name)
	}
	return integer, nil
}

func telemetryAttributeKeys(value string) ([]string, error) {
	parts := strings.Split(value, ",")
	if len(parts) < 1 || len(parts) > 32 {
		return nil, errors.New("--allowed-attribute-keys must contain 1 through 32 comma-separated keys")
	}
	keys := make([]string, 0, len(parts))
	seen := make(map[string]struct{}, len(parts))
	for _, part := range parts {
		key := strings.TrimSpace(part)
		if !telemetryAttributeKeyPattern.MatchString(key) || telemetrySensitiveAttributeKey(key) {
			return nil, errors.New("--allowed-attribute-keys must contain non-sensitive telemetry attribute keys")
		}
		if _, exists := seen[key]; exists {
			return nil, errors.New("--allowed-attribute-keys must not repeat a key")
		}
		seen[key] = struct{}{}
		keys = append(keys, key)
	}
	return keys, nil
}

func telemetrySensitiveAttributeKey(key string) bool {
	return strings.Contains(key, "password") || strings.Contains(key, "secret") || strings.Contains(key, "token") || strings.Contains(key, "credential") || strings.Contains(key, "authorization")
}

func requireOnlyFlags(flags map[string]string, permitted ...string) error {
	allowed := make(map[string]struct{}, len(permitted))
	for _, name := range permitted {
		allowed[name] = struct{}{}
	}
	for name := range flags {
		if _, exists := allowed[name]; !exists {
			return fmt.Errorf("unsupported command option %s", name)
		}
	}
	return nil
}

func validateLabResourceCommand(resourceType string, action string, cascade string) error {
	if resourceType != "lab-session" && resourceType != "lab-bed" && resourceType != "virtual-recorder" {
		return errors.New("--resource-type must be lab-session, lab-bed, or virtual-recorder")
	}
	switch action {
	case "start", "stop":
		if resourceType == "lab-bed" {
			return errors.New("--action start or stop requires resource type lab-session or virtual-recorder")
		}
	case "hide", "unhide":
		if resourceType == "lab-session" {
			return errors.New("--action hide or unhide requires resource type lab-bed or virtual-recorder")
		}
	case "detach":
		if resourceType != "virtual-recorder" {
			return errors.New("--action detach requires resource type virtual-recorder")
		}
	case "delete":
		expected := "none"
		if resourceType == "lab-session" {
			expected = "owned-resources"
		}
		if cascade != expected {
			return fmt.Errorf("--action delete requires --cascade %s", expected)
		}
		return nil
	default:
		return errors.New("--action must be start, stop, hide, unhide, detach, or delete")
	}
	if cascade != "" {
		return errors.New("--cascade is allowed only when --action delete")
	}
	return nil
}

// parseExternalUpstreamCommand carries only identifiers and references. The
// Guest configuration adapter owns the actual remote endpoint and credential
// material; platformctl deliberately has no URL, header, or secret option.
func parseExternalUpstreamCommand(invocation Invocation, command []string) (Invocation, error) {
	if len(command) == 0 || command[0] != "apply" {
		return Invocation{}, errors.New("external-upstream command must be apply")
	}
	flags, err := parseNamedFlags(command[1:])
	if err != nil {
		return Invocation{}, err
	}
	if err := requireOnlyFlags(flags,
		"--request-id", "--integration-id", "--expected-resource-revision",
		"--provider-kind", "--provider-id", "--provider-capability-revision",
		"--endpoint-resource-type", "--endpoint-resource-id",
		"--credential-kind", "--credential-id",
	); err != nil {
		return Invocation{}, err
	}
	requestID, err := requiredIdentifierFlag(flags, "--request-id")
	if err != nil {
		return Invocation{}, err
	}
	integrationID, err := requiredIdentifierFlag(flags, "--integration-id")
	if err != nil {
		return Invocation{}, err
	}
	revision, err := requiredNonNegativeRevision(flags, "--expected-resource-revision")
	if err != nil {
		return Invocation{}, err
	}
	provider, err := providerReferenceFromFlags(flags)
	if err != nil {
		return Invocation{}, err
	}
	endpoint, err := resourceReferenceFromFlags(flags, "--endpoint-resource-type", "--endpoint-resource-id")
	if err != nil {
		return Invocation{}, err
	}
	credential, err := optionalSecretReferenceFromFlags(flags)
	if err != nil {
		return Invocation{}, err
	}
	spec := map[string]any{"provider": provider, "endpointReference": endpoint}
	if credential != nil {
		spec["credentialReference"] = credential
	}
	body, err := json.Marshal(map[string]any{
		"schemaVersion": "v1", "requestId": requestID, "integrationId": integrationID,
		"expectedResourceRevision": revision, "spec": spec,
	})
	if err != nil {
		return Invocation{}, fmt.Errorf("encode external upstream apply command: %w", err)
	}
	invocation.Method = http.MethodPost
	invocation.Route = "/v1/runtime/external-upstreams"
	invocation.Body = body
	return invocation, nil
}

// parseTopologyCommand selects either a bundled provider reference supplied
// by a product deployment or an already-owned ExternalUpstreamIntegration.
// It never accepts a provider URL and never creates the external integration
// implicitly.
func parseTopologyCommand(invocation Invocation, command []string) (Invocation, error) {
	if len(command) == 0 || command[0] != "apply" {
		return Invocation{}, errors.New("topology command must be apply")
	}
	flags, err := parseNamedFlags(command[1:])
	if err != nil {
		return Invocation{}, err
	}
	if err := requireOnlyFlags(flags,
		"--request-id", "--topology-id", "--expected-resource-revision", "--profile-kind",
		"--endpoint-resource-type", "--endpoint-resource-id", "--credential-kind", "--credential-id",
	); err != nil {
		return Invocation{}, err
	}
	requestID, err := requiredIdentifierFlag(flags, "--request-id")
	if err != nil {
		return Invocation{}, err
	}
	topologyID, err := requiredIdentifierFlag(flags, "--topology-id")
	if err != nil {
		return Invocation{}, err
	}
	revision, err := requiredNonNegativeRevision(flags, "--expected-resource-revision")
	if err != nil {
		return Invocation{}, err
	}
	profileKind, err := requiredFlag(flags, "--profile-kind")
	if err != nil {
		return Invocation{}, err
	}
	if profileKind != "bundled-upstream" && profileKind != "external-upstream" {
		return Invocation{}, errors.New("--profile-kind must be bundled-upstream or external-upstream")
	}
	endpoint, err := resourceReferenceFromFlags(flags, "--endpoint-resource-type", "--endpoint-resource-id")
	if err != nil {
		return Invocation{}, err
	}
	if profileKind == "external-upstream" && endpoint["resourceType"] != "external-upstream-integration" {
		return Invocation{}, errors.New("external-upstream topology requires --endpoint-resource-type external-upstream-integration")
	}
	credential, err := optionalSecretReferenceFromFlags(flags)
	if err != nil {
		return Invocation{}, err
	}
	spec := map[string]any{"profileKind": profileKind, "providerKind": "vitalserver", "endpointReference": endpoint}
	if credential != nil {
		spec["credentialReference"] = credential
	}
	body, err := json.Marshal(map[string]any{
		"schemaVersion": "v1", "requestId": requestID, "topologyId": topologyID,
		"expectedResourceRevision": revision, "spec": spec,
	})
	if err != nil {
		return Invocation{}, fmt.Errorf("encode runtime topology apply command: %w", err)
	}
	invocation.Method = http.MethodPost
	invocation.Route = "/v1/runtime/topology:apply"
	invocation.Body = body
	return invocation, nil
}

func requiredNonNegativeRevision(flags map[string]string, name string) (int, error) {
	value, err := requiredFlag(flags, name)
	if err != nil {
		return 0, err
	}
	revision, err := strconv.Atoi(value)
	if err != nil || revision < 0 {
		return 0, fmt.Errorf("%s must be a non-negative integer", name)
	}
	return revision, nil
}

func providerReferenceFromFlags(flags map[string]string) (map[string]any, error) {
	kind, err := requiredIdentifierFlag(flags, "--provider-kind")
	if err != nil {
		return nil, err
	}
	id, err := requiredIdentifierFlag(flags, "--provider-id")
	if err != nil {
		return nil, err
	}
	revisionText, err := requiredFlag(flags, "--provider-capability-revision")
	if err != nil {
		return nil, err
	}
	revision, err := strconv.Atoi(revisionText)
	if err != nil || revision < 1 {
		return nil, errors.New("--provider-capability-revision must be a positive integer")
	}
	return map[string]any{"kind": kind, "id": id, "capabilityRevision": revision}, nil
}

func resourceReferenceFromFlags(flags map[string]string, typeFlag string, idFlag string) (map[string]any, error) {
	resourceType, err := requiredIdentifierFlag(flags, typeFlag)
	if err != nil {
		return nil, err
	}
	resourceID, err := requiredIdentifierFlag(flags, idFlag)
	if err != nil {
		return nil, err
	}
	return map[string]any{"resourceType": resourceType, "resourceId": resourceID}, nil
}

func optionalSecretReferenceFromFlags(flags map[string]string) (map[string]any, error) {
	kind, hasKind := flags["--credential-kind"]
	id, hasID := flags["--credential-id"]
	if !hasKind && !hasID {
		return nil, nil
	}
	if !hasKind || !hasID {
		return nil, errors.New("--credential-kind and --credential-id must be supplied together")
	}
	if !identifierPattern.MatchString(kind) || !identifierPattern.MatchString(id) {
		return nil, errors.New("credential reference values must be published identifiers")
	}
	return map[string]any{"kind": kind, "id": id}, nil
}
