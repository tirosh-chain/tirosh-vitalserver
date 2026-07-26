package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/guestpublicservicevirtiobridge"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/guestruntimecontrolvirtiolistener"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatepostgresqlmigration"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimecontrolhttpapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func main() {
	var processRole string
	var migrationPythonExecutablePath string
	var listenAddress string
	var controlVirtioSocketPort uint
	var publicServiceVirtioSocketBridgeArguments guestPublicServiceVirtioSocketBridgeArguments
	var stateDatabase string
	var recorderCatalogDatabaseURLMaterialPath string
	var recorderCatalogMigrationReceiptPath string
	var recorderCatalogAdmissionBearerTokenMaterialPath string
	var recorderObservationMaxReportAgeSeconds int
	var archiveSourceAdmissionBearerTokenMaterialPath string
	var archiveArtifactObjectRootDirectory string
	var archiveSourceMaximumBytes int64
	var labReplaySourceObjectRootDirectory string
	var labReplaySourceMaximumBytes int64
	var labReplaySpoolRootDirectory string
	var labReplayStringTrackPolicy string
	var labReplayGapPolicy string
	var labReplayFrameBatchSize int
	var recorderAttributionPolicyKind string
	var serviceVersion string
	var instanceID string
	var archiveProviderKind string
	var archiveProviderID string
	var archiveProviderRevision int
	var archiveProviderMode string
	var archiveProviderVitalServerConfigurationKind string
	var archiveProviderVitalServerConfigurationPath string
	var archiveProviderCredentialMaterialPath string
	var recorderGatewayColdPathSourceEndpoint string
	var labRecorderRunnerEndpoint string
	var externalUpstreamObservationProviderKind string
	var externalUpstreamObservationProviderID string
	var externalUpstreamObservationProviderRevision int
	var externalUpstreamObservationProviderMode string
	var externalUpstreamObservationExternalVitalServerDeliveryConfigurationPath string
	var externalUpstreamObservationRequestTimeoutMilliseconds int
	var outboundRelayObservationProviderKind string
	var outboundRelayObservationProviderID string
	var outboundRelayObservationProviderRevision int
	var outboundRelayObservationProviderMode string
	var guestNodeID string
	var timeAuthorityID string
	var timeAdapterKind string
	var timeChronyExecutablePath string
	var timeRequestTimeoutMilliseconds int
	var timeProviderMode string
	var telemetryAdapterKind string
	var telemetryCollectorBaseEndpoint string
	var telemetryRequestTimeoutMilliseconds int
	var telemetryPipelineMode string
	var telemetryExportMode string
	var guestOperationalStateBackupRootDirectory string
	var guestOperationalStateBackupLedgerDatabasePath string
	var guestOperationalStateBackupDestinationType string
	var guestOperationalStateBackupDestinationID string
	var guestOperationalStatePostgreSQLDumpExecutablePath string
	var guestOperationalStatePostgreSQLRestoreExecutablePath string
	var guestOperationalStateRestoreTargetType string
	var guestOperationalStateRestoreTargetID string
	var guestOperationalStateRestoreSQLiteTargetPath string
	var guestOperationalStateRestorePostgreSQLDatabaseURLMaterialPath string
	flag.StringVar(&processRole, "process-role", "", "required process role: runtime-control or recorder-catalog-migrator")
	flag.StringVar(&migrationPythonExecutablePath, "migration-python-executable", "", "required only for recorder-catalog-migrator: absolute Python executable with Alembic and Psycopg")
	flag.StringVar(&listenAddress, "listen", "", "required Guest Runtime control listen address")
	flag.UintVar(&controlVirtioSocketPort, "control-virtio-socket-port", 0, "required Guest Runtime control virtio-socket listener port")
	flag.Var(&publicServiceVirtioSocketBridgeArguments, "guest-public-service-virtio-socket-bridge", "required C37 public route as routeId,virtioSocketPort,127.0.0.1:targetPort; repeat for every route")
	flag.StringVar(&stateDatabase, "state-db", "", "required Guest Runtime-owned SQLite database path")
	flag.StringVar(&recorderCatalogDatabaseURLMaterialPath, "recorder-catalog-database-url-material-path", "", "required private file containing the Recorder Catalog PostgreSQL database URL")
	flag.StringVar(&recorderCatalogMigrationReceiptPath, "recorder-catalog-migration-receipt-path", "", "required private file containing the persisted Recorder Catalog migration receipt")
	flag.StringVar(&recorderCatalogAdmissionBearerTokenMaterialPath, "recorder-catalog-admission-bearer-token-material-path", "", "required private file containing the Recorder Gateway-to-Catalog bearer token")
	flag.IntVar(&recorderObservationMaxReportAgeSeconds, "recorder-observation-max-report-age-seconds", 0, "required explicit Recorder observation freshness threshold")
	flag.StringVar(&archiveSourceAdmissionBearerTokenMaterialPath, "archive-source-admission-bearer-token-material-path", "", "required private file containing the Recorder Gateway-to-Archive bearer token")
	flag.StringVar(&archiveArtifactObjectRootDirectory, "archive-artifact-object-root", "", "required Guest-owned Archive artifact object directory")
	flag.Int64Var(&archiveSourceMaximumBytes, "archive-source-max-bytes", 0, "required maximum Recorder Vital upload source bytes")
	flag.StringVar(&labReplaySourceObjectRootDirectory, "lab-replay-source-object-root", "", "required Guest-owned Lab replay source object directory")
	flag.Int64Var(&labReplaySourceMaximumBytes, "lab-replay-source-max-bytes", 0, "required maximum Lab replay source bytes")
	flag.StringVar(&labReplaySpoolRootDirectory, "lab-replay-spool-root", "", "required Guest-owned Lab replay spool directory")
	flag.StringVar(&labReplayStringTrackPolicy, "lab-replay-string-track-policy", "", "required Lab replay string-track policy: reject or skip")
	flag.StringVar(&labReplayGapPolicy, "lab-replay-gap-policy", "", "required Lab replay frame-gap policy: omit-track or fail-frame")
	flag.IntVar(&labReplayFrameBatchSize, "lab-replay-frame-batch-size", 0, "required Lab replay frames per real-time Runner batch; v1 requires exactly 1")
	flag.StringVar(&recorderAttributionPolicyKind, "recorder-attribution-policy-kind", "", "required explicit Recorder attribution policy kind")
	flag.StringVar(&serviceVersion, "service-version", "", "required Guest Runtime release version")
	flag.StringVar(&instanceID, "instance-id", "", "required Guest Runtime instance identifier")
	flag.StringVar(&archiveProviderKind, "archive-provider-kind", "", "required Archive Export provider kind")
	flag.StringVar(&archiveProviderID, "archive-provider-id", "", "required Archive Export provider id")
	flag.IntVar(&archiveProviderRevision, "archive-provider-capability-revision", 0, "required Archive Export provider capability revision")
	flag.StringVar(&archiveProviderMode, "archive-provider-mode", "", "required only for Archive Export outcome profile")
	flag.StringVar(&archiveProviderVitalServerConfigurationKind, "archive-provider-vitalserver-configuration-kind", "", "required only for VitalServer indexed-library Archive provider: external C46 or bundled C44 configuration kind")
	flag.StringVar(&archiveProviderVitalServerConfigurationPath, "archive-provider-vitalserver-configuration", "", "required only for VitalServer indexed-library Archive provider: absolute selected C44-or-C46 configuration path")
	flag.StringVar(&archiveProviderCredentialMaterialPath, "archive-provider-credential-material-path", "", "required only for VitalServer indexed-library Archive provider: private credential material path")
	flag.StringVar(&recorderGatewayColdPathSourceEndpoint, "recorder-gateway-cold-path-source-endpoint", "", "required Recorder Gateway Guest-loopback cold-path source endpoint")
	flag.StringVar(&labRecorderRunnerEndpoint, "lab-recorder-runner-endpoint", "", "required Lab recorder Runner Guest-loopback control endpoint")
	flag.StringVar(&externalUpstreamObservationProviderKind, "external-upstream-observation-provider-kind", "", "required External Upstream observation provider kind")
	flag.StringVar(&externalUpstreamObservationProviderID, "external-upstream-observation-provider-id", "", "required External Upstream observation provider id")
	flag.IntVar(&externalUpstreamObservationProviderRevision, "external-upstream-observation-provider-capability-revision", 0, "required External Upstream observation provider capability revision")
	flag.StringVar(&externalUpstreamObservationProviderMode, "external-upstream-observation-provider-mode", "", "required only for the External Upstream outcome profile")
	flag.StringVar(&externalUpstreamObservationExternalVitalServerDeliveryConfigurationPath, "external-upstream-observation-external-vitalserver-delivery-configuration", "", "required only for External VitalServer HTTP observation: absolute C46 configuration path")
	flag.IntVar(&externalUpstreamObservationRequestTimeoutMilliseconds, "external-upstream-observation-request-timeout-milliseconds", 0, "required only for External VitalServer HTTP observation")
	flag.StringVar(&outboundRelayObservationProviderKind, "outbound-relay-observation-provider-kind", "", "required Outbound Relay observation provider kind")
	flag.StringVar(&outboundRelayObservationProviderID, "outbound-relay-observation-provider-id", "", "required Outbound Relay observation provider id")
	flag.IntVar(&outboundRelayObservationProviderRevision, "outbound-relay-observation-provider-capability-revision", 0, "required Outbound Relay observation provider capability revision")
	flag.StringVar(&outboundRelayObservationProviderMode, "outbound-relay-observation-provider-mode", "", "required Outbound Relay observation provider outcome mode")
	flag.StringVar(&guestNodeID, "guest-node-id", "", "required Guest node identifier for time and telemetry resources")
	flag.StringVar(&timeAuthorityID, "time-authority-id", "", "required Guest TimeAuthority identifier used by clock-quality reads")
	flag.StringVar(&timeAdapterKind, "time-adapter-kind", "", "required Guest Time Authority adapter kind: time-authority-outcome-profile or chrony-tracking")
	flag.StringVar(&timeChronyExecutablePath, "time-chrony-executable-path", "", "required only for the Chrony Time Authority adapter")
	flag.IntVar(&timeRequestTimeoutMilliseconds, "time-request-timeout-milliseconds", 0, "required only for the Chrony Time Authority adapter")
	flag.StringVar(&timeProviderMode, "time-provider-mode", "", "required only for the Time Authority outcome profile")
	flag.StringVar(&telemetryAdapterKind, "telemetry-adapter-kind", "", "required Guest telemetry adapter kind: telemetry-export-outcome-profile or otlp-http")
	flag.StringVar(&telemetryCollectorBaseEndpoint, "telemetry-collector-base-endpoint", "", "required only for the OTLP HTTP telemetry adapter")
	flag.IntVar(&telemetryRequestTimeoutMilliseconds, "telemetry-request-timeout-milliseconds", 0, "required only for the OTLP HTTP telemetry adapter")
	flag.StringVar(&telemetryPipelineMode, "telemetry-pipeline-mode", "", "required only for the telemetry outcome profile")
	flag.StringVar(&telemetryExportMode, "telemetry-export-mode", "", "required only for the telemetry outcome profile")
	flag.StringVar(&guestOperationalStateBackupRootDirectory, "operational-state-backup-root", "", "optional as a complete set: absolute immutable C76 backup root")
	flag.StringVar(&guestOperationalStateBackupLedgerDatabasePath, "operational-state-backup-ledger-db", "", "optional as a complete set: C76 ledger outside the snapshotted Guest Runtime database")
	flag.StringVar(&guestOperationalStateBackupDestinationType, "operational-state-backup-destination-type", "", "optional as a complete set: immutable destination resource type")
	flag.StringVar(&guestOperationalStateBackupDestinationID, "operational-state-backup-destination-id", "", "optional as a complete set: immutable destination resource id")
	flag.StringVar(&guestOperationalStatePostgreSQLDumpExecutablePath, "operational-state-pg-dump-executable", "", "optional as a complete set: absolute pg_dump executable")
	flag.StringVar(&guestOperationalStatePostgreSQLRestoreExecutablePath, "operational-state-pg-restore-executable", "", "optional as a complete set: absolute pg_restore executable used to prove the dump")
	flag.StringVar(&guestOperationalStateRestoreTargetType, "operational-state-restore-target-type", "", "optional as a complete set: explicitly provisioned empty restore target resource type")
	flag.StringVar(&guestOperationalStateRestoreTargetID, "operational-state-restore-target-id", "", "optional as a complete set: explicitly provisioned empty restore target resource id")
	flag.StringVar(&guestOperationalStateRestoreSQLiteTargetPath, "operational-state-restore-sqlite-target", "", "optional as a complete set: absent SQLite target path")
	flag.StringVar(&guestOperationalStateRestorePostgreSQLDatabaseURLMaterialPath, "operational-state-restore-postgresql-database-url-material-path", "", "optional as a complete set: private file containing the empty PostgreSQL target URL")
	flag.Parse()
	if processRole == "recorder-catalog-migrator" {
		if migrationPythonExecutablePath == "" ||
			recorderCatalogDatabaseURLMaterialPath == "" {
			fmt.Fprintln(
				os.Stderr,
				"Recorder Catalog migrator requires --migration-python-executable and --recorder-catalog-database-url-material-path",
			)
			os.Exit(2)
		}
		recorderCatalogDatabaseURL, err := readExactPrivateMaterial(
			recorderCatalogDatabaseURLMaterialPath,
			"Recorder Catalog PostgreSQL database URL",
		)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(2)
		}
		receipt, err := gueststatepostgresqlmigration.ApplyRecorderCatalogMigrations(
			context.Background(),
			gueststatepostgresqlmigration.RecorderCatalogMigrationConfiguration{
				PythonExecutablePath: migrationPythonExecutablePath,
				DatabaseURL:          recorderCatalogDatabaseURL,
			},
		)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Recorder Catalog migration failed: %v\n", err)
			os.Exit(1)
		}
		encoded, err := json.Marshal(receipt)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Recorder Catalog migration receipt encode failed: %v\n", err)
			os.Exit(1)
		}
		fmt.Println(string(encoded))
		return
	}
	if processRole != "runtime-control" {
		fmt.Fprintln(os.Stderr, "Guest Runtime --process-role must be runtime-control or recorder-catalog-migrator")
		os.Exit(2)
	}
	if missing := missingRequiredGuestRuntimeFlags([]requiredGuestRuntimeFlag{
		{name: "--listen", value: listenAddress}, {name: "--control-virtio-socket-port", value: fmt.Sprintf("%d", controlVirtioSocketPort)}, {name: "--state-db", value: stateDatabase}, {name: "--recorder-catalog-database-url-material-path", value: recorderCatalogDatabaseURLMaterialPath}, {name: "--recorder-catalog-migration-receipt-path", value: recorderCatalogMigrationReceiptPath}, {name: "--recorder-catalog-admission-bearer-token-material-path", value: recorderCatalogAdmissionBearerTokenMaterialPath}, {name: "--service-version", value: serviceVersion}, {name: "--instance-id", value: instanceID},
		{name: "--archive-source-admission-bearer-token-material-path", value: archiveSourceAdmissionBearerTokenMaterialPath}, {name: "--archive-artifact-object-root", value: archiveArtifactObjectRootDirectory}, {name: "--archive-source-max-bytes", value: fmt.Sprintf("%d", archiveSourceMaximumBytes)}, {name: "--lab-replay-source-object-root", value: labReplaySourceObjectRootDirectory}, {name: "--lab-replay-source-max-bytes", value: fmt.Sprintf("%d", labReplaySourceMaximumBytes)}, {name: "--lab-replay-spool-root", value: labReplaySpoolRootDirectory}, {name: "--lab-replay-string-track-policy", value: labReplayStringTrackPolicy}, {name: "--lab-replay-gap-policy", value: labReplayGapPolicy}, {name: "--lab-replay-frame-batch-size", value: fmt.Sprintf("%d", labReplayFrameBatchSize)}, {name: "--recorder-attribution-policy-kind", value: recorderAttributionPolicyKind},
		{name: "--archive-provider-kind", value: archiveProviderKind}, {name: "--archive-provider-id", value: archiveProviderID}, {name: "--recorder-gateway-cold-path-source-endpoint", value: recorderGatewayColdPathSourceEndpoint}, {name: "--lab-recorder-runner-endpoint", value: labRecorderRunnerEndpoint},
		{name: "--external-upstream-observation-provider-kind", value: externalUpstreamObservationProviderKind}, {name: "--external-upstream-observation-provider-id", value: externalUpstreamObservationProviderID},
		{name: "--outbound-relay-observation-provider-kind", value: outboundRelayObservationProviderKind}, {name: "--outbound-relay-observation-provider-id", value: outboundRelayObservationProviderID}, {name: "--outbound-relay-observation-provider-mode", value: outboundRelayObservationProviderMode},
		{name: "--guest-node-id", value: guestNodeID}, {name: "--time-authority-id", value: timeAuthorityID}, {name: "--time-adapter-kind", value: timeAdapterKind},
		{name: "--telemetry-adapter-kind", value: telemetryAdapterKind},
	}); len(missing) > 0 || controlVirtioSocketPort > uint(^uint16(0)) || archiveSourceMaximumBytes < 1 || labReplayFrameBatchSize != 1 || archiveProviderRevision < 1 || externalUpstreamObservationProviderRevision < 1 || outboundRelayObservationProviderRevision < 1 || !completeArchiveProviderFlags(archiveProviderKind, archiveProviderMode, archiveProviderVitalServerConfigurationKind, archiveProviderVitalServerConfigurationPath, archiveProviderCredentialMaterialPath) || !completeExternalUpstreamObservationProviderFlags(externalUpstreamObservationProviderKind, externalUpstreamObservationProviderMode, externalUpstreamObservationExternalVitalServerDeliveryConfigurationPath, externalUpstreamObservationRequestTimeoutMilliseconds) || !completeTimeAuthorityAdapterFlags(timeAdapterKind, timeChronyExecutablePath, timeRequestTimeoutMilliseconds, timeProviderMode) || !completeTelemetryAdapterFlags(telemetryAdapterKind, telemetryCollectorBaseEndpoint, telemetryRequestTimeoutMilliseconds, telemetryPipelineMode, telemetryExportMode) {
		fmt.Fprintln(os.Stderr, "Guest Runtime required configuration is incomplete; every provider reference, selected adapter, TCP listener, virtio-socket listener, state store, time, and telemetry setting must be explicit")
		os.Exit(2)
	}
	publicServiceVirtioSocketBridges, err := parseGuestPublicServiceVirtioSocketBridgeArguments(publicServiceVirtioSocketBridgeArguments)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Guest Runtime public service transport configuration is invalid: %v\n", err)
		os.Exit(2)
	}
	for _, publicServiceVirtioSocketBridge := range publicServiceVirtioSocketBridges {
		if publicServiceVirtioSocketBridge.VirtioSocketPort == uint32(controlVirtioSocketPort) {
			fmt.Fprintln(os.Stderr, "Guest Runtime public service transport cannot reuse the control virtio-socket port")
			os.Exit(2)
		}
	}
	recorderCatalogDatabaseURL, err := readExactPrivateMaterial(
		recorderCatalogDatabaseURLMaterialPath,
		"Recorder Catalog PostgreSQL database URL",
	)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	recorderCatalogAdmissionBearerToken, err := readExactPrivateMaterial(
		recorderCatalogAdmissionBearerTokenMaterialPath,
		"Recorder Catalog admission bearer token",
	)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	archiveSourceAdmissionBearerToken, err := readExactPrivateMaterial(
		archiveSourceAdmissionBearerTokenMaterialPath,
		"Archive source admission bearer token",
	)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	guestOperationalStateRestorePostgreSQLDatabaseURL := ""
	if guestOperationalStateRestorePostgreSQLDatabaseURLMaterialPath != "" {
		guestOperationalStateRestorePostgreSQLDatabaseURL, err =
			readExactPrivateMaterial(
				guestOperationalStateRestorePostgreSQLDatabaseURLMaterialPath,
				"Guest operational-state restore PostgreSQL database URL",
			)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(2)
		}
	}

	guestRuntimeProcessContext, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	guestRuntimeControlApplication, err := guestruntimecontrolhttpapplication.OpenGuestRuntimeControlHTTPApplication(
		guestRuntimeProcessContext,
		guestruntimecontrolhttpapplication.GuestRuntimeControlHTTPApplicationDeployment{
			GuestRuntimeStateDatabasePath:                                           stateDatabase,
			RecorderCatalogPostgreSQLDatabaseURL:                                    recorderCatalogDatabaseURL,
			RecorderCatalogDatabaseURLMaterialPath:                                  recorderCatalogDatabaseURLMaterialPath,
			RecorderCatalogMigrationReceiptPath:                                     recorderCatalogMigrationReceiptPath,
			RecorderCatalogAdmissionBearerToken:                                     recorderCatalogAdmissionBearerToken,
			RecorderCatalogAdmissionBearerTokenMaterialPath:                         recorderCatalogAdmissionBearerTokenMaterialPath,
			RecorderObservationMaxReportAgeSeconds:                                  recorderObservationMaxReportAgeSeconds,
			ArchiveSourceAdmissionBearerToken:                                       archiveSourceAdmissionBearerToken,
			ArchiveSourceAdmissionBearerTokenMaterialPath:                           archiveSourceAdmissionBearerTokenMaterialPath,
			ArchiveArtifactObjectRootDirectory:                                      archiveArtifactObjectRootDirectory,
			ArchiveSourceMaximumBytes:                                               archiveSourceMaximumBytes,
			LabReplaySourceObjectRootDirectory:                                      labReplaySourceObjectRootDirectory,
			LabReplaySourceMaximumBytes:                                             labReplaySourceMaximumBytes,
			LabReplaySpoolRootDirectory:                                             labReplaySpoolRootDirectory,
			LabReplayStringTrackPolicy:                                              labReplayStringTrackPolicy,
			LabReplayGapPolicy:                                                      labReplayGapPolicy,
			LabReplayFrameBatchSize:                                                 labReplayFrameBatchSize,
			RecorderAttributionPolicyKind:                                           recorderAttributionPolicyKind,
			GuestRuntimeServiceVersion:                                              serviceVersion,
			GuestRuntimeInstanceID:                                                  instanceID,
			ArchiveExportProviderReference:                                          guestruntimedomain.ArchiveProviderReference{Kind: archiveProviderKind, ID: archiveProviderID, CapabilityRevision: archiveProviderRevision},
			ArchiveExportProviderOutcomeMode:                                        archiveProviderMode,
			ArchiveProviderVitalServerConfigurationKind:                             archiveProviderVitalServerConfigurationKind,
			ArchiveProviderVitalServerConfigurationPath:                             archiveProviderVitalServerConfigurationPath,
			ArchiveProviderCredentialMaterialPath:                                   archiveProviderCredentialMaterialPath,
			RecorderGatewayColdPathSourceEndpoint:                                   recorderGatewayColdPathSourceEndpoint,
			LabRecorderRunnerEndpoint:                                               labRecorderRunnerEndpoint,
			ExternalUpstreamObservationProviderReference:                            guestruntimedomain.IntegrationProviderReference{Kind: externalUpstreamObservationProviderKind, ID: externalUpstreamObservationProviderID, CapabilityRevision: externalUpstreamObservationProviderRevision},
			ExternalUpstreamObservationProviderOutcomeMode:                          externalUpstreamObservationProviderMode,
			ExternalUpstreamObservationExternalVitalServerDeliveryConfigurationPath: externalUpstreamObservationExternalVitalServerDeliveryConfigurationPath,
			ExternalUpstreamObservationRequestTimeoutMilliseconds:                   externalUpstreamObservationRequestTimeoutMilliseconds,
			OutboundRelayObservationProviderReference:                               guestruntimedomain.IntegrationProviderReference{Kind: outboundRelayObservationProviderKind, ID: outboundRelayObservationProviderID, CapabilityRevision: outboundRelayObservationProviderRevision},
			OutboundRelayObservationProviderOutcomeMode:                             outboundRelayObservationProviderMode,
			GuestRuntimeNode:                                                        guestruntimedomain.NodeReference{Kind: "guest", ID: guestNodeID},
			GuestTimeAuthorityID:                                                    timeAuthorityID,
			GuestTimeAuthorityAdapterKind:                                           timeAdapterKind,
			GuestTimeAuthorityChronyExecutablePath:                                  timeChronyExecutablePath,
			GuestTimeAuthorityRequestTimeoutMilliseconds:                            timeRequestTimeoutMilliseconds,
			GuestTimeAuthorityProbeOutcomeMode:                                      timeProviderMode,
			GuestTelemetryAdapterKind:                                               telemetryAdapterKind,
			GuestTelemetryCollectorBaseEndpoint:                                     telemetryCollectorBaseEndpoint,
			GuestTelemetryRequestTimeoutMilliseconds:                                telemetryRequestTimeoutMilliseconds,
			GuestTelemetryCollectorProbeOutcomeMode:                                 telemetryPipelineMode,
			GuestTelemetryExportOutcomeMode:                                         telemetryExportMode,
			GuestOperationalStateBackupRootDirectory:                                guestOperationalStateBackupRootDirectory,
			GuestOperationalStateBackupLedgerDatabasePath:                           guestOperationalStateBackupLedgerDatabasePath,
			GuestOperationalStateBackupDestinationReference:                         guestruntimedomain.ResourceReference{ResourceType: guestOperationalStateBackupDestinationType, ResourceID: guestOperationalStateBackupDestinationID},
			GuestOperationalStatePostgreSQLDumpExecutablePath:                       guestOperationalStatePostgreSQLDumpExecutablePath,
			GuestOperationalStatePostgreSQLRestoreExecutablePath:                    guestOperationalStatePostgreSQLRestoreExecutablePath,
			GuestOperationalStateRestoreTargetReference:                             guestruntimedomain.ResourceReference{ResourceType: guestOperationalStateRestoreTargetType, ResourceID: guestOperationalStateRestoreTargetID},
			GuestOperationalStateRestoreSQLiteTargetPath:                            guestOperationalStateRestoreSQLiteTargetPath,
			GuestOperationalStateRestorePostgreSQLDatabaseURL:                       guestOperationalStateRestorePostgreSQLDatabaseURL,
		},
	)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Guest Runtime control application open failed: %v\n", err)
		os.Exit(1)
	}
	defer func() {
		if closeError := guestRuntimeControlApplication.CloseGuestRuntimeControlHTTPApplication(); closeError != nil {
			fmt.Fprintf(os.Stderr, "Guest Runtime control application shutdown failed: %v\n", closeError)
		}
	}()
	if reconciliationError := guestRuntimeControlApplication.ReconcilePendingTerminalArchiveExports(guestRuntimeProcessContext); reconciliationError != nil {
		// Lab and Archive keep the underlying terminal intent durable and
		// operator-readable. Do not claim that startup repaired it; serving the
		// control API lets an operator inspect and explicitly retry the exact
		// idempotent stop/archive request after the dependency recovers.
		fmt.Fprintf(os.Stderr, "Guest Runtime terminal Archive reconciliation was not completed: %v\n", reconciliationError)
	}
	tcpListener, err := net.Listen("tcp", listenAddress)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Guest Runtime TCP control listener failed: %v\n", err)
		os.Exit(1)
	}
	virtioSocketListener, err := guestruntimecontrolvirtiolistener.ListenGuestRuntimeControlVirtioSocket(uint32(controlVirtioSocketPort))
	if err != nil {
		_ = tcpListener.Close()
		fmt.Fprintf(os.Stderr, "Guest Runtime virtio-socket control listener failed: %v\n", err)
		os.Exit(1)
	}
	tcpControlHTTPServer := &http.Server{Handler: guestRuntimeControlApplication.ControlHTTPHandler}
	virtioSocketControlHTTPServer := &http.Server{Handler: guestRuntimeControlApplication.ControlHTTPHandler}
	serveErrors := make(chan error, 2+len(publicServiceVirtioSocketBridges))
	serveGuestRuntimeControlHTTP := func(server *http.Server, listener net.Listener, boundary string) {
		if serveError := server.Serve(listener); serveError != nil && !errors.Is(serveError, http.ErrServerClosed) {
			serveErrors <- fmt.Errorf("Guest Runtime %s control server failed: %w", boundary, serveError)
		}
	}
	go serveGuestRuntimeControlHTTP(tcpControlHTTPServer, tcpListener, "TCP")
	go serveGuestRuntimeControlHTTP(virtioSocketControlHTTPServer, virtioSocketListener, "virtio-socket")
	for _, publicServiceVirtioSocketBridge := range publicServiceVirtioSocketBridges {
		go runGuestPublicServiceVirtioSocketBridge(guestRuntimeProcessContext, publicServiceVirtioSocketBridge, serveErrors)
	}
	fmt.Printf("guest-runtime TCP control listening address=%s\n", tcpListener.Addr().String())
	fmt.Printf("guest-runtime virtio-socket control listening port=%d\n", controlVirtioSocketPort)
	go func() {
		<-guestRuntimeProcessContext.Done()
		_ = tcpControlHTTPServer.Shutdown(guestRuntimeProcessContext)
		_ = virtioSocketControlHTTPServer.Shutdown(guestRuntimeProcessContext)
	}()
	select {
	case serveError := <-serveErrors:
		_ = tcpControlHTTPServer.Shutdown(guestRuntimeProcessContext)
		_ = virtioSocketControlHTTPServer.Shutdown(guestRuntimeProcessContext)
		fmt.Fprintf(os.Stderr, "%v\n", serveError)
		os.Exit(1)
	case <-guestRuntimeProcessContext.Done():
	}
}

func readExactPrivateMaterial(path string, description string) (string, error) {
	contents, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("%s material read failed: %w", description, err)
	}
	value := string(contents)
	if value == "" || strings.TrimSpace(value) != value {
		return "", fmt.Errorf(
			"%s material must contain one exact non-empty value without surrounding whitespace",
			description,
		)
	}
	return value, nil
}

func completeArchiveProviderFlags(kind string, outcomeMode string, vitalServerConfigurationKind string, vitalServerConfigurationPath string, credentialMaterialPath string) bool {
	switch kind {
	case "archive-export-outcome-profile":
		return outcomeMode != "" && vitalServerConfigurationKind == "" && vitalServerConfigurationPath == "" && credentialMaterialPath == ""
	case "vitalserver-indexed-library":
		return outcomeMode == "" && (vitalServerConfigurationKind == "external-vitalserver-delivery-configuration" || vitalServerConfigurationKind == "bundled-vitalserver-topology-deployment") && vitalServerConfigurationPath != "" && credentialMaterialPath != ""
	default:
		return false
	}
}

func completeExternalUpstreamObservationProviderFlags(kind string, outcomeMode string, externalVitalServerDeliveryConfigurationPath string, requestTimeoutMilliseconds int) bool {
	switch kind {
	case "external-capability-profile":
		return outcomeMode != "" && externalVitalServerDeliveryConfigurationPath == "" && requestTimeoutMilliseconds == 0
	case "external-vitalserver-http":
		return outcomeMode == "" && externalVitalServerDeliveryConfigurationPath != "" && requestTimeoutMilliseconds >= 1 && requestTimeoutMilliseconds <= 60000
	default:
		return false
	}
}

func completeTelemetryAdapterFlags(kind string, collectorBaseEndpoint string, requestTimeoutMilliseconds int, pipelineMode string, exportMode string) bool {
	switch kind {
	case "telemetry-export-outcome-profile":
		return collectorBaseEndpoint == "" && requestTimeoutMilliseconds == 0 && pipelineMode != "" && exportMode != ""
	case "otlp-http":
		return collectorBaseEndpoint != "" && requestTimeoutMilliseconds >= 1 && requestTimeoutMilliseconds <= 60000 && pipelineMode == "" && exportMode == ""
	default:
		return false
	}
}

func completeTimeAuthorityAdapterFlags(kind string, chronyExecutablePath string, requestTimeoutMilliseconds int, outcomeMode string) bool {
	switch kind {
	case "time-authority-outcome-profile":
		return chronyExecutablePath == "" && requestTimeoutMilliseconds == 0 && outcomeMode != ""
	case "chrony-tracking":
		return chronyExecutablePath != "" && requestTimeoutMilliseconds >= 1 && requestTimeoutMilliseconds <= 60000 && outcomeMode == ""
	default:
		return false
	}
}

func runGuestPublicServiceVirtioSocketBridge(context context.Context, configuration guestpublicservicevirtiobridge.GuestPublicServiceVirtioSocketBridgeConfiguration, serveErrors chan<- error) {
	if err := guestpublicservicevirtiobridge.RunGuestPublicServiceVirtioSocketBridge(context, configuration); err != nil && context.Err() == nil {
		serveErrors <- fmt.Errorf("Guest public service route %s transport failed: %w", configuration.RouteID, err)
	}
}

type requiredGuestRuntimeFlag struct {
	name  string
	value string
}

func missingRequiredGuestRuntimeFlags(flags []requiredGuestRuntimeFlag) []string {
	missing := make([]string, 0)
	for _, candidate := range flags {
		if candidate.value == "" {
			missing = append(missing, candidate.name)
		}
	}
	return missing
}
