// guest-runtime-control-http-acceptance-fixture composes the real Guest
// Runtime application services behind their public HTTP contract for
// cross-host acceptance tests. It is not a production Guest process entry
// point: it deliberately does not bind the Linux-only virtio-socket transport.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimecontrolhttpapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func main() {
	var listenAddress string
	var stateDatabase string
	var bootstrapEvidenceRootDirectory string
	var recorderCatalogDatabaseURL string
	var recorderCatalogAdmissionBearerToken string
	var recorderObservationMaxReportAgeSeconds int
	var archiveSourceAdmissionBearerToken string
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
	flag.StringVar(&listenAddress, "listen", "", "required acceptance fixture TCP control listen address")
	flag.StringVar(&stateDatabase, "state-db", "", "required Guest Runtime-owned SQLite database path")
	flag.StringVar(&bootstrapEvidenceRootDirectory, "bootstrap-evidence-root", "", "required acceptance-only explicit root for synthetic bootstrap evidence")
	flag.StringVar(&recorderCatalogDatabaseURL, "recorder-catalog-database-url", "", "required Recorder Catalog PostgreSQL database URL")
	flag.StringVar(&recorderCatalogAdmissionBearerToken, "recorder-catalog-admission-bearer-token", "", "required acceptance-only Recorder Gateway-to-Catalog bearer token")
	flag.IntVar(&recorderObservationMaxReportAgeSeconds, "recorder-observation-max-report-age-seconds", 0, "required explicit Recorder observation freshness threshold")
	flag.StringVar(&archiveSourceAdmissionBearerToken, "archive-source-admission-bearer-token", "", "required acceptance-only Recorder Gateway-to-Archive bearer token")
	flag.StringVar(&archiveArtifactObjectRootDirectory, "archive-artifact-object-root", "", "required Guest-owned Archive artifact object directory")
	flag.Int64Var(&archiveSourceMaximumBytes, "archive-source-max-bytes", 0, "required maximum Recorder Vital upload source bytes")
	flag.StringVar(&labReplaySourceObjectRootDirectory, "lab-replay-source-object-root", "", "required Guest-owned Lab replay source object directory")
	flag.Int64Var(&labReplaySourceMaximumBytes, "lab-replay-source-max-bytes", 0, "required maximum Lab replay source bytes")
	flag.StringVar(&labReplaySpoolRootDirectory, "lab-replay-spool-root", "", "required Guest-owned Lab replay spool directory")
	flag.StringVar(&labReplayStringTrackPolicy, "lab-replay-string-track-policy", "", "required Lab replay string-track policy")
	flag.StringVar(&labReplayGapPolicy, "lab-replay-gap-policy", "", "required Lab replay frame-gap policy")
	flag.IntVar(&labReplayFrameBatchSize, "lab-replay-frame-batch-size", 0, "required Lab replay frames per real-time Runner batch; v1 requires exactly 1")
	flag.StringVar(&recorderAttributionPolicyKind, "recorder-attribution-policy-kind", "", "required explicit Recorder attribution policy kind")
	flag.StringVar(&serviceVersion, "service-version", "", "required Guest Runtime release version")
	flag.StringVar(&instanceID, "instance-id", "", "required Guest Runtime instance identifier")
	flag.StringVar(&archiveProviderKind, "archive-provider-kind", "", "required Archive Export provider kind")
	flag.StringVar(&archiveProviderID, "archive-provider-id", "", "required Archive Export provider id")
	flag.IntVar(&archiveProviderRevision, "archive-provider-capability-revision", 0, "required Archive Export provider capability revision")
	flag.StringVar(&archiveProviderMode, "archive-provider-mode", "", "required only for Archive Export outcome profile")
	flag.StringVar(&archiveProviderVitalServerConfigurationKind, "archive-provider-vitalserver-configuration-kind", "", "required only for VitalServer indexed-library Archive provider")
	flag.StringVar(&archiveProviderVitalServerConfigurationPath, "archive-provider-vitalserver-configuration", "", "required only for VitalServer indexed-library Archive provider")
	flag.StringVar(&archiveProviderCredentialMaterialPath, "archive-provider-credential-material-path", "", "required only for VitalServer indexed-library Archive provider")
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
	flag.StringVar(&guestNodeID, "guest-node-id", "", "required Guest node identifier for Time and Telemetry resources")
	flag.StringVar(&timeAuthorityID, "time-authority-id", "", "required Guest Time Authority identifier used by clock-quality reads")
	flag.StringVar(&timeAdapterKind, "time-adapter-kind", "", "required Guest Time Authority adapter kind")
	flag.StringVar(&timeChronyExecutablePath, "time-chrony-executable-path", "", "required only for the Chrony Time Authority adapter")
	flag.IntVar(&timeRequestTimeoutMilliseconds, "time-request-timeout-milliseconds", 0, "required only for the Chrony Time Authority adapter")
	flag.StringVar(&timeProviderMode, "time-provider-mode", "", "required only for the Time Authority outcome profile")
	flag.StringVar(&telemetryAdapterKind, "telemetry-adapter-kind", "", "required Guest telemetry adapter kind")
	flag.StringVar(&telemetryCollectorBaseEndpoint, "telemetry-collector-base-endpoint", "", "required only for the OTLP HTTP telemetry adapter")
	flag.IntVar(&telemetryRequestTimeoutMilliseconds, "telemetry-request-timeout-milliseconds", 0, "required only for the OTLP HTTP telemetry adapter")
	flag.StringVar(&telemetryPipelineMode, "telemetry-pipeline-mode", "", "required only for the telemetry outcome profile")
	flag.StringVar(&telemetryExportMode, "telemetry-export-mode", "", "required only for the telemetry outcome profile")
	flag.Parse()
	if missing := missingRequiredGuestRuntimeControlHTTPAcceptanceFixtureFlags([]requiredGuestRuntimeControlHTTPAcceptanceFixtureFlag{
		{name: "--listen", value: listenAddress}, {name: "--state-db", value: stateDatabase}, {name: "--bootstrap-evidence-root", value: bootstrapEvidenceRootDirectory}, {name: "--recorder-catalog-database-url", value: recorderCatalogDatabaseURL}, {name: "--recorder-catalog-admission-bearer-token", value: recorderCatalogAdmissionBearerToken}, {name: "--service-version", value: serviceVersion}, {name: "--instance-id", value: instanceID},
		{name: "--archive-source-admission-bearer-token", value: archiveSourceAdmissionBearerToken}, {name: "--archive-artifact-object-root", value: archiveArtifactObjectRootDirectory}, {name: "--lab-replay-source-object-root", value: labReplaySourceObjectRootDirectory}, {name: "--lab-replay-spool-root", value: labReplaySpoolRootDirectory}, {name: "--lab-replay-string-track-policy", value: labReplayStringTrackPolicy}, {name: "--lab-replay-gap-policy", value: labReplayGapPolicy}, {name: "--lab-replay-frame-batch-size", value: fmt.Sprintf("%d", labReplayFrameBatchSize)}, {name: "--recorder-attribution-policy-kind", value: recorderAttributionPolicyKind},
		{name: "--archive-provider-kind", value: archiveProviderKind}, {name: "--archive-provider-id", value: archiveProviderID}, {name: "--recorder-gateway-cold-path-source-endpoint", value: recorderGatewayColdPathSourceEndpoint}, {name: "--lab-recorder-runner-endpoint", value: labRecorderRunnerEndpoint},
		{name: "--external-upstream-observation-provider-kind", value: externalUpstreamObservationProviderKind}, {name: "--external-upstream-observation-provider-id", value: externalUpstreamObservationProviderID},
		{name: "--outbound-relay-observation-provider-kind", value: outboundRelayObservationProviderKind}, {name: "--outbound-relay-observation-provider-id", value: outboundRelayObservationProviderID}, {name: "--outbound-relay-observation-provider-mode", value: outboundRelayObservationProviderMode},
		{name: "--guest-node-id", value: guestNodeID}, {name: "--time-authority-id", value: timeAuthorityID}, {name: "--time-adapter-kind", value: timeAdapterKind},
		{name: "--telemetry-adapter-kind", value: telemetryAdapterKind},
	}); len(missing) > 0 || archiveSourceMaximumBytes < 1 || archiveProviderRevision < 1 || externalUpstreamObservationProviderRevision < 1 || outboundRelayObservationProviderRevision < 1 || !completeArchiveProviderFlags(archiveProviderKind, archiveProviderMode, archiveProviderVitalServerConfigurationKind, archiveProviderVitalServerConfigurationPath, archiveProviderCredentialMaterialPath) || !completeExternalUpstreamObservationProviderFlags(externalUpstreamObservationProviderKind, externalUpstreamObservationProviderMode, externalUpstreamObservationExternalVitalServerDeliveryConfigurationPath, externalUpstreamObservationRequestTimeoutMilliseconds) || !completeTimeAuthorityAdapterFlags(timeAdapterKind, timeChronyExecutablePath, timeRequestTimeoutMilliseconds, timeProviderMode) || !completeTelemetryAdapterFlags(telemetryAdapterKind, telemetryCollectorBaseEndpoint, telemetryRequestTimeoutMilliseconds, telemetryPipelineMode, telemetryExportMode) {
		fmt.Fprintln(os.Stderr, "Guest Runtime Control HTTP acceptance fixture requires every application deployment setting explicitly; this fixture does not create a Guest virtio-socket listener")
		os.Exit(2)
	}
	bootstrapEvidence, err := materializeAcceptanceBootstrapEvidence(
		bootstrapEvidenceRootDirectory,
		recorderCatalogDatabaseURL,
		recorderCatalogAdmissionBearerToken,
		archiveSourceAdmissionBearerToken,
	)
	if err != nil {
		fmt.Fprintf(
			os.Stderr,
			"Guest Runtime Control HTTP acceptance fixture bootstrap evidence failed: %v\n",
			err,
		)
		os.Exit(1)
	}

	acceptanceFixtureContext, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	guestRuntimeControlApplication, err := guestruntimecontrolhttpapplication.OpenGuestRuntimeControlHTTPApplication(
		acceptanceFixtureContext,
		guestruntimecontrolhttpapplication.GuestRuntimeControlHTTPApplicationDeployment{
			GuestRuntimeStateDatabasePath:                                           stateDatabase,
			RecorderCatalogPostgreSQLDatabaseURL:                                    recorderCatalogDatabaseURL,
			RecorderCatalogDatabaseURLMaterialPath:                                  bootstrapEvidence.databaseURLMaterialPath,
			RecorderCatalogMigrationReceiptPath:                                     bootstrapEvidence.migrationReceiptPath,
			RecorderCatalogAdmissionBearerToken:                                     recorderCatalogAdmissionBearerToken,
			RecorderCatalogAdmissionBearerTokenMaterialPath:                         bootstrapEvidence.catalogAdmissionTokenMaterialPath,
			RecorderObservationMaxReportAgeSeconds:                                  recorderObservationMaxReportAgeSeconds,
			ArchiveSourceAdmissionBearerToken:                                       archiveSourceAdmissionBearerToken,
			ArchiveSourceAdmissionBearerTokenMaterialPath:                           bootstrapEvidence.archiveAdmissionTokenMaterialPath,
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
		},
	)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Guest Runtime Control HTTP acceptance fixture application open failed: %v\n", err)
		os.Exit(1)
	}
	defer func() {
		if closeError := guestRuntimeControlApplication.CloseGuestRuntimeControlHTTPApplication(); closeError != nil {
			fmt.Fprintf(os.Stderr, "Guest Runtime Control HTTP acceptance fixture shutdown failed: %v\n", closeError)
		}
	}()
	controlHTTPListener, err := net.Listen("tcp", listenAddress)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Guest Runtime Control HTTP acceptance fixture TCP listener failed: %v\n", err)
		os.Exit(1)
	}
	controlHTTPServer := &http.Server{Handler: guestRuntimeControlApplication.ControlHTTPHandler}
	serveError := make(chan error, 1)
	go func() {
		if serverError := controlHTTPServer.Serve(controlHTTPListener); serverError != nil && !errors.Is(serverError, http.ErrServerClosed) {
			serveError <- fmt.Errorf("Guest Runtime Control HTTP acceptance fixture server failed: %w", serverError)
		}
	}()
	fmt.Printf("guest-runtime-control-http-acceptance-fixture TCP control listening address=%s\n", controlHTTPListener.Addr().String())
	select {
	case serverError := <-serveError:
		_ = controlHTTPServer.Shutdown(acceptanceFixtureContext)
		fmt.Fprintln(os.Stderr, serverError)
		os.Exit(1)
	case <-acceptanceFixtureContext.Done():
		_ = controlHTTPServer.Shutdown(acceptanceFixtureContext)
	}
}

type acceptanceBootstrapEvidence struct {
	databaseURLMaterialPath           string
	catalogAdmissionTokenMaterialPath string
	archiveAdmissionTokenMaterialPath string
	migrationReceiptPath              string
}

func materializeAcceptanceBootstrapEvidence(
	root string,
	databaseURL string,
	catalogAdmissionToken string,
	archiveAdmissionToken string,
) (acceptanceBootstrapEvidence, error) {
	if !filepath.IsAbs(root) || filepath.Clean(root) != root {
		return acceptanceBootstrapEvidence{},
			fmt.Errorf("acceptance bootstrap evidence root must be an explicit absolute path")
	}
	if err := os.MkdirAll(root, 0o700); err != nil {
		return acceptanceBootstrapEvidence{}, err
	}
	evidence := acceptanceBootstrapEvidence{
		databaseURLMaterialPath: filepath.Join(
			root,
			"recorder-catalog-database-url",
		),
		catalogAdmissionTokenMaterialPath: filepath.Join(
			root,
			"recorder-catalog-admission-token",
		),
		archiveAdmissionTokenMaterialPath: filepath.Join(
			root,
			"archive-source-admission-token",
		),
		migrationReceiptPath: filepath.Join(
			root,
			"recorder-catalog-migration-receipt.json",
		),
	}
	for path, contents := range map[string]string{
		evidence.databaseURLMaterialPath:           databaseURL,
		evidence.catalogAdmissionTokenMaterialPath: catalogAdmissionToken,
		evidence.archiveAdmissionTokenMaterialPath: archiveAdmissionToken,
		evidence.migrationReceiptPath:              `{"schemaVersion":"v1","state":"succeeded","revision":"0006_backup_owner","startedAt":"2026-07-24T00:00:00Z","finishedAt":"2026-07-24T00:00:01Z"}`,
	} {
		if err := os.WriteFile(path, []byte(contents), 0o600); err != nil {
			return acceptanceBootstrapEvidence{}, err
		}
	}
	return evidence, nil
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

type requiredGuestRuntimeControlHTTPAcceptanceFixtureFlag struct {
	name  string
	value string
}

func missingRequiredGuestRuntimeControlHTTPAcceptanceFixtureFlags(flags []requiredGuestRuntimeControlHTTPAcceptanceFixtureFlag) []string {
	missing := make([]string, 0)
	for _, candidate := range flags {
		if candidate.value == "" {
			missing = append(missing, candidate.name)
		}
	}
	return missing
}
