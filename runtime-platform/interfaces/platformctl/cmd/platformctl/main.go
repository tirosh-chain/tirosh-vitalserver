// platformctl is the explicit, headless operator interface for the Host Agent
// Control API. It does not own product state.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/platformctl/internal/platformctlcommand"
	"github.com/tirosh-chain/vitalserver-runtime-platform/platformctl/internal/platformctlcontrolclient"
)

const usage = `Usage:
  platformctl --local-control-descriptor <absolute-path> installation
  platformctl --local-control-descriptor <absolute-path> guest-runtime-control-endpoint
  platformctl --local-control-descriptor <absolute-path> guest <start|stop|reboot> --request-id <id> --guest-runtime-control-endpoint-id <id> --expected-resource-revision <revision>
  platformctl --local-control-descriptor <absolute-path> operation <host|runtime> --operation-id <id>
  platformctl --local-control-descriptor <absolute-path> runtime <readiness|topology|capabilities|lab-sessions|lab-beds|lab-recorders|archive-export-provider|external-upstreams|outbound-relays|recorder-observations|guest-clock-quality>
  platformctl --local-control-descriptor <absolute-path> host-clock-quality
  platformctl --local-control-descriptor <absolute-path> update import --request-id <id> --source-directory <absolute-host-directory>
  platformctl --local-control-descriptor <absolute-path> update read --bundle-id <id>
  platformctl --local-control-descriptor <absolute-path> update apply --request-id <id> --installation-id <id> --expected-installation-revision <revision> --bundle-id <id>
  platformctl --local-control-descriptor <absolute-path> lab create --request-id <id> --session-id <id> --name <base-name> --scenario <scenario-id> --recorder-count <1..64>
  platformctl --local-control-descriptor <absolute-path> lab resource --request-id <id> --resource-type <lab-session|lab-bed|virtual-recorder> --resource-id <id> --expected-resource-revision <revision> --action <start|stop|hide|unhide|detach|delete> [--cascade <none|owned-resources>]
  platformctl --local-control-descriptor <absolute-path> archive credential-material
  printf '%s\\n' '<password>' | platformctl --local-control-descriptor <absolute-path> archive credential-material provision --credential-kind <id> --credential-id <id> --user-id <id> --password-stdin true
  platformctl --local-control-descriptor <absolute-path> archive export --request-id <id> --virtual-recorder-id <id> --expected-resource-revision <revision> --cold-path-finalization-receipt-id <id> --provider-kind <id> --provider-id <id> --provider-capability-revision <revision>
  platformctl --local-control-descriptor <absolute-path> external-upstream apply --request-id <id> --integration-id <id> --expected-resource-revision <revision> --provider-kind <id> --provider-id <id> --provider-capability-revision <revision> --endpoint-resource-type <id> --endpoint-resource-id <id> [--credential-kind <id> --credential-id <id>]
  platformctl --local-control-descriptor <absolute-path> topology apply --request-id <id> --topology-id <id> --expected-resource-revision <revision> --profile-kind <bundled-upstream|external-upstream> --endpoint-resource-type <id> --endpoint-resource-id <id> [--credential-kind <id> --credential-id <id>]
  platformctl --local-control-descriptor <absolute-path> time apply --scope <host|guest> --request-id <id> --authority-id <id> --expected-resource-revision <revision> --node-kind <id> --node-id <id> --profile <id> --source-profile <id> --source-id <id>
  platformctl --local-control-descriptor <absolute-path> telemetry apply --scope <host|guest> --request-id <id> --pipeline-id <id> --expected-resource-revision <revision> --node-kind <id> --node-id <id> --collector-resource-type <id> --collector-resource-id <id> --allowed-attribute-keys <comma-separated-keys> --max-attributes <1..32> --max-value-length <1..256> --max-distinct-values-per-key <1..100>

  # Explicit development-only loopback facade; it is not OS authorization.
  platformctl --control-endpoint <http://127.0.0.1:port> <same command>
`

func main() {
	if err := run(os.Args[1:], os.Stdout, os.Stderr); err != nil {
		fmt.Fprintln(os.Stderr, "platformctl:", err)
		os.Exit(1)
	}
}

func run(arguments []string, stdout io.Writer, stderr io.Writer) error {
	return runWithInput(arguments, os.Stdin, stdout, stderr)
}

func runWithInput(arguments []string, stdin io.Reader, stdout io.Writer, stderr io.Writer) error {
	if len(arguments) == 1 && (arguments[0] == "help" || arguments[0] == "--help" || arguments[0] == "-h") {
		_, _ = io.WriteString(stdout, usage)
		return nil
	}
	invocation, err := platformctlcommand.Parse(arguments)
	if err != nil {
		_, _ = io.WriteString(stderr, usage)
		return err
	}
	endpoint, client, err := controlClientForInvocation(invocation)
	if err != nil {
		return err
	}
	invocation, err = materializePasswordFromStandardInput(invocation, stdin)
	if err != nil {
		return err
	}
	response, requestErr := client.Execute(context.Background(), endpoint, invocation.Method, invocation.Route, invocation.Body)
	if response.Document != nil {
		if err := writeResponse(stdout, response); err != nil {
			return err
		}
	}
	if requestErr != nil {
		var statusError *platformctlcontrolclient.ResponseStatusError
		if errors.As(requestErr, &statusError) {
			return statusError
		}
		return requestErr
	}
	return nil
}

// materializePasswordFromStandardInput is the outer CLI transport boundary for
// one explicitly selected Archive credential-material provision command. It
// reads neither a file nor an environment variable and never echoes the
// secret. The parsed invocation deliberately contains no password until this
// function receives one bounded, single-line stdin value.
func materializePasswordFromStandardInput(invocation platformctlcommand.Invocation, stdin io.Reader) (platformctlcommand.Invocation, error) {
	if !invocation.ReadsPasswordFromStandardInput {
		return invocation, nil
	}
	if stdin == nil {
		return platformctlcommand.Invocation{}, errors.New("archive credential-material provisioning requires standard input")
	}
	encoded, err := io.ReadAll(io.LimitReader(stdin, 4099))
	if err != nil {
		return platformctlcommand.Invocation{}, fmt.Errorf("read archive credential password from standard input: %w", err)
	}
	if len(encoded) > 4098 {
		return platformctlcommand.Invocation{}, errors.New("archive credential password exceeds 4096 bytes")
	}
	password := strings.TrimSuffix(string(encoded), "\n")
	password = strings.TrimSuffix(password, "\r")
	if password == "" || len(password) > 4096 || strings.ContainsAny(password, "\x00\r\n") {
		return platformctlcommand.Invocation{}, errors.New("archive credential password must be a bounded non-empty single line")
	}
	decoder := json.NewDecoder(bytes.NewReader(invocation.Body))
	decoder.DisallowUnknownFields()
	var body struct {
		SchemaVersion       string `json:"schemaVersion"`
		CredentialReference struct {
			Kind string `json:"kind"`
			ID   string `json:"id"`
		} `json:"credentialReference"`
		UserID string `json:"userId"`
	}
	if err := decoder.Decode(&body); err != nil {
		return platformctlcommand.Invocation{}, errors.New("archive credential-material parser body is invalid")
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) || body.SchemaVersion != "v1" || body.CredentialReference.Kind == "" || body.CredentialReference.ID == "" || body.UserID == "" {
		return platformctlcommand.Invocation{}, errors.New("archive credential-material parser body is incomplete")
	}
	invocation.Body, err = json.Marshal(struct {
		SchemaVersion       string `json:"schemaVersion"`
		CredentialReference struct {
			Kind string `json:"kind"`
			ID   string `json:"id"`
		} `json:"credentialReference"`
		UserID   string `json:"userId"`
		Password string `json:"password"`
	}{SchemaVersion: body.SchemaVersion, CredentialReference: body.CredentialReference, UserID: body.UserID, Password: password})
	if err != nil {
		return platformctlcommand.Invocation{}, fmt.Errorf("encode archive credential-material command: %w", err)
	}
	invocation.ReadsPasswordFromStandardInput = false
	return invocation, nil
}

func controlClientForInvocation(invocation platformctlcommand.Invocation) (platformctlcontrolclient.LocalControlEndpoint, *platformctlcontrolclient.Client, error) {
	if invocation.LocalControlDescriptorPath != "" {
		endpoint, err := platformctlcontrolclient.LoadLocalAdministrationEndpointDescriptor(invocation.LocalControlDescriptorPath)
		if err != nil {
			return platformctlcontrolclient.LocalControlEndpoint{}, nil, err
		}
		client, err := platformctlcontrolclient.NewClientForLocalAdministrationEndpoint(endpoint, 10*time.Second)
		return endpoint, client, err
	}
	endpoint, err := platformctlcontrolclient.ParseLocalControlEndpoint(invocation.ControlEndpoint)
	if err != nil {
		return platformctlcontrolclient.LocalControlEndpoint{}, nil, err
	}
	client, err := platformctlcontrolclient.NewClient(&http.Client{Timeout: 10 * time.Second})
	return endpoint, client, err
}

func writeResponse(writer io.Writer, response platformctlcontrolclient.Response) error {
	output := struct {
		HTTPStatus int             `json:"httpStatus"`
		Document   json.RawMessage `json:"document"`
	}{HTTPStatus: response.HTTPStatus, Document: response.Document}
	encoder := json.NewEncoder(writer)
	encoder.SetIndent("", "  ")
	return encoder.Encode(output)
}
