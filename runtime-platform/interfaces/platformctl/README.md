# platformctl

`platformctl` is the headless operator interface for the Runtime Platform.

It consumes only the published Host Agent Control API. It has no database,
does not read a Host deployment file, and does not inspect a Guest process,
filesystem, or log. A response is printed as the owner supplied it, with the
HTTP status alongside it; the CLI does not turn an unavailable, failed, or
stale response into a summary success.

## Explicit connection boundary

Every production invocation requires `--local-control-descriptor`, an absolute
path to the Host Agent's C52 descriptor. C52 names exactly one Unix domain
socket (macOS/Linux) or Windows named pipe. It contains no remote address,
Host deployment configuration, authorization policy, or secret. `platformctl`
accepts a regular, non-symlink, exact C52 JSON document only and disables
environment proxy selection for this local transport.

The descriptor path is still explicit command input: `platformctl` never reads
C33, scans installation directories, infers a port, or opens a remote control
address. The Host Agent listener enforces Unix peer-user or Windows pipe-ACL
authorization before public control HTTP reaches the command owner.

`--control-endpoint http://127.0.0.1:<port>` remains a deliberately explicit
development-only adapter. It accepts only a numeric loopback HTTP address and
is not a per-user authorization boundary.

## Installed location

The Host installer includes this CLI in its immutable release slot at
`current/bin/platformctl` (`platformctl.exe` on Windows). It is not a Host
service and has no installation-time state of its own. Operators must still
name the C52 descriptor explicitly for every production invocation.

## Commands

```sh
# Read Host-owned resources.
platformctl --local-control-descriptor /absolute/path/host-agent.local.json installation
platformctl --local-control-descriptor /absolute/path/host-agent.local.json guest-runtime-control-endpoint

# Request a Host-owned Guest lifecycle action. The current endpoint identity
# and revision come from the resource read above; they are never guessed.
platformctl --local-control-descriptor /absolute/path/host-agent.local.json guest start \
  --request-id operator-start-20260719-001 \
  --guest-runtime-control-endpoint-id guest-runtime-control \
  --expected-resource-revision 3

# Read a Host or Guest durable operation through the same public facade.
platformctl --local-control-descriptor /absolute/path/host-agent.local.json operation host \
  --operation-id host-operation-001
platformctl --control-endpoint http://127.0.0.1:18280 operation runtime \
  --operation-id runtime-operation-001

# Read Guest-owned product resources through the Host allowlist.
platformctl --local-control-descriptor /absolute/path/host-agent.local.json runtime readiness
platformctl --local-control-descriptor /absolute/path/host-agent.local.json runtime topology
platformctl --local-control-descriptor /absolute/path/host-agent.local.json runtime capabilities

# Inspect owner-published operational state. These commands do not inspect
# SQLite, logs, recorder sockets, or upstream endpoints directly.
platformctl --local-control-descriptor /absolute/path/host-agent.local.json host-clock-quality
platformctl --local-control-descriptor /absolute/path/host-agent.local.json runtime guest-clock-quality
platformctl --local-control-descriptor /absolute/path/host-agent.local.json runtime lab-sessions
platformctl --local-control-descriptor /absolute/path/host-agent.local.json runtime lab-beds
platformctl --local-control-descriptor /absolute/path/host-agent.local.json runtime lab-recorders
platformctl --local-control-descriptor /absolute/path/host-agent.local.json runtime archive-export-provider
platformctl --local-control-descriptor /absolute/path/host-agent.local.json runtime recorder-observations
platformctl --local-control-descriptor /absolute/path/host-agent.local.json runtime external-upstreams
platformctl --local-control-descriptor /absolute/path/host-agent.local.json runtime outbound-relays

# Apply a Host or Guest NTP source by its deployment-owned source identity.
# Neither command accepts an NTP address, port, or credential.
platformctl --local-control-descriptor /absolute/path/host-agent.local.json time apply \
  --scope host \
  --request-id operator-host-time-20260720-001 \
  --authority-id host-time-authority \
  --expected-resource-revision 0 \
  --node-kind host \
  --node-id vitalserver-host \
  --profile enterprise-ntp \
  --source-profile enterprise-ntp \
  --source-id hospital-ntp-primary

# Apply an OTLP pipeline. The public command fixes the signal set to logs,
# metrics, and traces; it carries a collector reference and a bounded
# non-sensitive attribute allowlist, never a collector URL or secret.
platformctl --local-control-descriptor /absolute/path/host-agent.local.json telemetry apply \
  --scope guest \
  --request-id operator-guest-telemetry-20260720-001 \
  --pipeline-id guest-telemetry \
  --expected-resource-revision 0 \
  --node-kind guest \
  --node-id vitalserver-guest \
  --collector-resource-type otel-collector \
  --collector-resource-id platform-collector \
  --allowed-attribute-keys operation.kind,outcome.code \
  --max-attributes 8 \
  --max-value-length 128 \
  --max-distinct-values-per-key 32

# Create a prepared Lab aggregate. The Guest owns the visible LAB- name
# prefix and the identities of its child beds and virtual recorders.
platformctl --local-control-descriptor /absolute/path/host-agent.local.json lab create \
  --request-id operator-lab-create-20260720-001 \
  --session-id lab-session-baseline-001 \
  --name baseline-monitoring \
  --scenario baseline-monitoring \
  --recorder-count 3

# Read Lab resources first, then carry the owner-published identity and
# revision into one exact lifecycle action. Delete requires the Guest-defined
# cascade instead of a CLI default.
platformctl --local-control-descriptor /absolute/path/host-agent.local.json runtime lab-sessions
platformctl --local-control-descriptor /absolute/path/host-agent.local.json lab resource \
  --request-id operator-lab-start-20260720-001 \
  --resource-type lab-session \
  --resource-id lab-session-baseline-001 \
  --expected-resource-revision 1 \
  --action start
platformctl --local-control-descriptor /absolute/path/host-agent.local.json lab resource \
  --request-id operator-lab-delete-20260720-001 \
  --resource-type lab-session \
  --resource-id lab-session-baseline-001 \
  --expected-resource-revision 2 \
  --action delete \
  --cascade owned-resources

# Manual archive export is intentionally distinct from stopping a Lab
# recorder. Read the stopped virtual recorder and the Archive-owned provider
# first, then copy their exact owner-published IDs/revisions/receipt. This is
# valid only for terminalArchivePolicy=no-export; export-on-stop has its own
# durable terminal intent and must not be submitted a second time.
platformctl --local-control-descriptor /absolute/path/host-agent.local.json runtime lab-recorders
platformctl --local-control-descriptor /absolute/path/host-agent.local.json runtime archive-export-provider
platformctl --local-control-descriptor /absolute/path/host-agent.local.json archive credential-material
# Provision a private Archive credential only through the authorized local
# facade. `platformctl` reads exactly one password line from stdin; it has no
# password argv, file-path, or environment-variable option.
printf '%s\n' "$VITALSERVER_ARCHIVE_PASSWORD" | \
  platformctl --local-control-descriptor /absolute/path/host-agent.local.json archive credential-material provision \
    --credential-kind vitalserver-library-credential \
    --credential-id external-vitalserver-primary-library \
    --user-id archive-operator \
    --password-stdin true
platformctl --local-control-descriptor /absolute/path/host-agent.local.json archive export \
  --request-id operator-archive-export-20260720-001 \
  --virtual-recorder-id recorder-001 \
  --expected-resource-revision 4 \
  --cold-path-finalization-receipt-id cold-path-finalization-001 \
  --provider-kind vitalserver-indexed-library \
  --provider-id primary-library \
  --provider-capability-revision 1

# Configure an external VitalServer only by references to its reviewed Guest
# delivery configuration and private credential material. The CLI deliberately
# has no external URL, header, or password argument.
platformctl --local-control-descriptor /absolute/path/host-agent.local.json external-upstream apply \
  --request-id operator-external-upstream-20260720-001 \
  --integration-id external-vitalserver-primary \
  --expected-resource-revision 0 \
  --provider-kind external-vitalserver \
  --provider-id external-vitalserver-primary \
  --provider-capability-revision 1 \
  --endpoint-resource-type external-vitalserver-delivery-configuration \
  --endpoint-resource-id external-vitalserver-primary-delivery \
  --credential-kind vitalserver-library-credential \
  --credential-id external-vitalserver-primary-library

# Apply the topology only after the external integration has returned an
# explicit operation outcome. A bundled topology is also allowed, but its
# endpoint reference must be supplied by the selected bundled deployment.
platformctl --local-control-descriptor /absolute/path/host-agent.local.json topology apply \
  --request-id operator-topology-20260720-001 \
  --topology-id primary-topology \
  --expected-resource-revision 0 \
  --profile-kind external-upstream \
  --endpoint-resource-type external-upstream-integration \
  --endpoint-resource-id external-vitalserver-primary

# Importing only atomically copies a complete bundle into the Host-owned
# store. It does not claim release trust verification or update success.
platformctl --local-control-descriptor /absolute/path/host-agent.local.json update import \
  --request-id operator-import-20260720-001 \
  --source-directory /absolute/path/to/signed-release-bundle

# The Host reads its own imported C25 declaration. The operator explicitly
# supplies the current C7 installation identity/revision; platformctl does not
# guess either field from a previous response.
platformctl --local-control-descriptor /absolute/path/host-agent.local.json update read \
  --bundle-id release-bootstrap-020
platformctl --local-control-descriptor /absolute/path/host-agent.local.json update apply \
  --request-id operator-update-20260720-001 \
  --installation-id vitalserver-runtime-platform-macos-bundled-reference \
  --expected-installation-revision 1 \
  --bundle-id release-bootstrap-020
```

The process exit code is non-zero for a transport, decode, or non-2xx HTTP
failure. The printed document is still preserved for a typed 4xx/5xx response;
the exit code is not a replacement for its contract state.

`archive export` has no Gateway URL, raw payload, local cold-path filename,
archive endpoint, or credential option. These values remain owned by Recorder
Gateway, the Archive provider deployment, and the secret-material boundary.
Credential provisioning is the separate named exception: its credential
reference is explicit and its one password value is consumed from stdin only,
immediately before the local Host facade request. `platformctl` never reads a
password file or environment variable and never prints the supplied password.

See [Operator Control Surface](../../../docs/architecture/operator-control-surface.md)
for the common Console/CLI boundary and the desktop-console design.
