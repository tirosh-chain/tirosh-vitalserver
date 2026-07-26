// Package guestruntimecontrolhttpapplication composes the Guest Runtime
// application services that own the versioned Guest Runtime Control HTTP
// contract. It deliberately owns no TCP or virtio-socket listener: those
// transport bindings belong to distinct process entry points.
package guestruntimecontrolhttpapplication

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"path/filepath"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/archiveartifactobjectfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/archiveprovider"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/externalupstreamobservationprovider"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/guestbootstrapidentityfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatebackupsqliterepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatebackupstageexecutor"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatepostgresqlbackup"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatepostgresqlrepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatepostgresqlrestore"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatesqliterepository"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/gueststatesqliterestore"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/labrecorderrunner"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/labreplaysourcefile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/outboundrelayobservationprovider"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/recorderassignmentresolution"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/recordergatewaycoldpathsource"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/telemetryexporter"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/timeprovider"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/vitalartifactformation"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/vitalfilereplayparser"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/vitalfilereplayspoolsqlite"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/vitalserverindexedlibrary"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimecontrolhttpapi"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

// GuestRuntimeControlHTTPApplicationDeployment is the complete desired input
// required to compose Guest Runtime application services behind the control
// HTTP contract. It is not a process transport declaration or a readiness
// observation.
type GuestRuntimeControlHTTPApplicationDeployment struct {
	GuestRuntimeStateDatabasePath                                           string
	RecorderCatalogPostgreSQLDatabaseURL                                    string
	RecorderCatalogDatabaseURLMaterialPath                                  string
	RecorderCatalogMigrationReceiptPath                                     string
	RecorderCatalogAdmissionBearerToken                                     string
	RecorderCatalogAdmissionBearerTokenMaterialPath                         string
	RecorderObservationMaxReportAgeSeconds                                  int
	ArchiveSourceAdmissionBearerToken                                       string
	ArchiveSourceAdmissionBearerTokenMaterialPath                           string
	ArchiveArtifactObjectRootDirectory                                      string
	ArchiveSourceMaximumBytes                                               int64
	LabReplaySourceObjectRootDirectory                                      string
	LabReplaySourceMaximumBytes                                             int64
	LabReplaySpoolRootDirectory                                             string
	LabReplayStringTrackPolicy                                              string
	LabReplayGapPolicy                                                      string
	LabReplayFrameBatchSize                                                 int
	RecorderAttributionPolicyKind                                           string
	GuestRuntimeServiceVersion                                              string
	GuestRuntimeInstanceID                                                  string
	ArchiveExportProviderReference                                          guestruntimedomain.ArchiveProviderReference
	ArchiveExportProviderOutcomeMode                                        string
	ArchiveProviderVitalServerConfigurationKind                             string
	ArchiveProviderVitalServerConfigurationPath                             string
	ArchiveProviderCredentialMaterialPath                                   string
	RecorderGatewayColdPathSourceEndpoint                                   string
	LabRecorderRunnerEndpoint                                               string
	ExternalUpstreamObservationProviderReference                            guestruntimedomain.IntegrationProviderReference
	ExternalUpstreamObservationProviderOutcomeMode                          string
	ExternalUpstreamObservationExternalVitalServerDeliveryConfigurationPath string
	ExternalUpstreamObservationRequestTimeoutMilliseconds                   int
	OutboundRelayObservationProviderReference                               guestruntimedomain.IntegrationProviderReference
	OutboundRelayObservationProviderOutcomeMode                             string
	GuestRuntimeNode                                                        guestruntimedomain.NodeReference
	GuestTimeAuthorityID                                                    string
	GuestTimeAuthorityAdapterKind                                           string
	GuestTimeAuthorityChronyExecutablePath                                  string
	GuestTimeAuthorityRequestTimeoutMilliseconds                            int
	GuestTimeAuthorityProbeOutcomeMode                                      string
	GuestTelemetryAdapterKind                                               string
	GuestTelemetryCollectorBaseEndpoint                                     string
	GuestTelemetryRequestTimeoutMilliseconds                                int
	GuestTelemetryCollectorProbeOutcomeMode                                 string
	GuestTelemetryExportOutcomeMode                                         string
	GuestOperationalStateBackupRootDirectory                                string
	GuestOperationalStateBackupLedgerDatabasePath                           string
	GuestOperationalStateBackupDestinationReference                         guestruntimedomain.ResourceReference
	GuestOperationalStatePostgreSQLDumpExecutablePath                       string
	GuestOperationalStatePostgreSQLRestoreExecutablePath                    string
	GuestOperationalStateRestoreTargetReference                             guestruntimedomain.ResourceReference
	GuestOperationalStateRestoreSQLiteTargetPath                            string
	GuestOperationalStateRestorePostgreSQLDatabaseURL                       string
}

// GuestRuntimeControlHTTPApplication exposes the composed HTTP handler and
// owns the lifecycle of the Guest Runtime SQLite control ledger and PostgreSQL
// Recorder Catalog repositories it opened.
type GuestRuntimeControlHTTPApplication struct {
	ControlHTTPHandler           http.Handler
	guestRuntimeStateRepository  *gueststatesqliterepository.GuestRuntimeStateSQLiteRepository
	recorderCatalogRepository    recorderCatalogRepository
	archiveLineageRepository     archiveLineageRepository
	recorderAssignmentRepository recorderAssignmentRepository
	reconcileTerminalArchives    func(context.Context) error
	runNextLabReplayEffect       func(context.Context) (guestruntimedomain.LabReplayOperation, bool, error)
	stopLabReplayWorker          context.CancelFunc
	labReplayWorkerDone          chan struct{}
	guestOperationalStateLedger  *gueststatebackupsqliterepository.Repository
	guestOperationalStateBackup  *gueststatepostgresqlbackup.Owner
	guestOperationalStateRestore *gueststatepostgresqlrestore.Owner
	runNextGuestStateEffect      func(context.Context) (guestruntimedomain.GuestOperationalStateBackupOperation, bool, error)
	stopGuestStateWorker         context.CancelFunc
	guestStateWorkerDone         chan struct{}
}

type recorderCatalogRepository interface {
	guestruntimeapplication.GuestRuntimeObservationCatalogStateRepository
	guestruntimeapplication.GuestRuntimePostgreSQLIdentityReader
	guestruntimeapplication.GuestRuntimeReadinessDependency
	Close() error
}

type archiveLineageRepository interface {
	guestruntimeapplication.GuestRuntimeArchiveLineageRepository
	guestruntimeapplication.GuestRuntimeArchiveSourceAdmissionRepository
	guestruntimeapplication.GuestOperationalStateArtifactInventoryOwner
	guestruntimeapplication.GuestRuntimeReadinessDependency
	Close() error
}

type recorderAssignmentRepository interface {
	guestruntimeapplication.GuestRuntimeRecorderAssignmentRepository
	guestruntimeapplication.GuestRuntimeReadinessDependency
	Close() error
}

// OpenGuestRuntimeControlHTTPApplication opens the explicitly named Guest
// Runtime state owner and assembles its control HTTP application modules. It
// does not bind a transport listener or infer any provider outcome.
func OpenGuestRuntimeControlHTTPApplication(
	compositionContext context.Context,
	deployment GuestRuntimeControlHTTPApplicationDeployment,
) (*GuestRuntimeControlHTTPApplication, error) {
	if err := validateGuestRuntimeControlHTTPApplicationDeployment(deployment); err != nil {
		return nil, err
	}
	guestRuntimeStateRepository, err := gueststatesqliterepository.OpenGuestRuntimeStateSQLiteRepository(
		compositionContext,
		deployment.GuestRuntimeStateDatabasePath,
	)
	if err != nil {
		return nil, fmt.Errorf("open Guest Runtime state repository: %w", err)
	}
	recorderCatalogRepository, err := gueststatepostgresqlrepository.OpenRecorderCatalogPostgreSQLRepository(
		compositionContext,
		deployment.RecorderCatalogPostgreSQLDatabaseURL,
	)
	if err != nil {
		_ = guestRuntimeStateRepository.Close()
		return nil, fmt.Errorf("open Recorder Catalog repository: %w", err)
	}
	archiveLineageRepository, err := gueststatepostgresqlrepository.OpenArchiveExportPostgreSQLRepository(
		compositionContext,
		deployment.RecorderCatalogPostgreSQLDatabaseURL,
	)
	if err != nil {
		_ = recorderCatalogRepository.Close()
		_ = guestRuntimeStateRepository.Close()
		return nil, fmt.Errorf("open Archive Export lineage repository: %w", err)
	}
	recorderAssignmentRepository, err := gueststatepostgresqlrepository.OpenRecorderAssignmentPostgreSQLRepository(
		compositionContext,
		deployment.RecorderCatalogPostgreSQLDatabaseURL,
	)
	if err != nil {
		_ = archiveLineageRepository.Close()
		_ = recorderCatalogRepository.Close()
		_ = guestRuntimeStateRepository.Close()
		return nil, fmt.Errorf("open Recorder Assignment repository: %w", err)
	}

	controlApplication, err := openGuestRuntimeControlHTTPApplicationWithRepositories(
		guestRuntimeStateRepository,
		recorderCatalogRepository,
		archiveLineageRepository,
		recorderAssignmentRepository,
		deployment,
	)
	if err != nil {
		return nil, err
	}
	controlApplication.startLabReplayWorker(compositionContext)
	controlApplication.startGuestOperationalStateWorker(compositionContext)
	return controlApplication, nil
}

func openGuestRuntimeControlHTTPApplicationWithRepositories(
	guestRuntimeStateRepository *gueststatesqliterepository.GuestRuntimeStateSQLiteRepository,
	recorderCatalogRepository recorderCatalogRepository,
	archiveLineageRepository archiveLineageRepository,
	recorderAssignmentRepository recorderAssignmentRepository,
	deployment GuestRuntimeControlHTTPApplicationDeployment,
) (*GuestRuntimeControlHTTPApplication, error) {
	var guestOperationalStateService *guestruntimeapplication.GuestOperationalStateBackupApplicationService
	var guestOperationalStateLedger *gueststatebackupsqliterepository.Repository
	var guestOperationalStateBackupOwner *gueststatepostgresqlbackup.Owner
	var guestOperationalStateRestoreOwner *gueststatepostgresqlrestore.Owner
	if guestOperationalStateBackupConfigured(deployment) {
		var err error
		guestOperationalStateLedger, err = gueststatebackupsqliterepository.Open(
			context.Background(),
			deployment.GuestOperationalStateBackupLedgerDatabasePath,
		)
		if err != nil {
			closeGuestRuntimeRepositories(
				guestRuntimeStateRepository,
				recorderCatalogRepository,
				archiveLineageRepository,
				recorderAssignmentRepository,
			)
			return nil, fmt.Errorf(
				"open Guest operational-state backup ledger: %w",
				err,
			)
		}
		guestOperationalStateBackupOwner, err = gueststatepostgresqlbackup.Open(
			context.Background(),
			gueststatepostgresqlbackup.Configuration{
				DatabaseURL: deployment.RecorderCatalogPostgreSQLDatabaseURL,
				PGDumpExecutablePath: deployment.
					GuestOperationalStatePostgreSQLDumpExecutablePath,
				PGRestoreExecutablePath: deployment.
					GuestOperationalStatePostgreSQLRestoreExecutablePath,
				ExpectedAlembicRevision: gueststatepostgresqlrepository.
					ExpectedRecorderCatalogRevision,
			},
		)
		if err != nil {
			_ = guestOperationalStateLedger.Close()
			closeGuestRuntimeRepositories(
				guestRuntimeStateRepository,
				recorderCatalogRepository,
				archiveLineageRepository,
				recorderAssignmentRepository,
			)
			return nil, fmt.Errorf(
				"open Guest operational-state PostgreSQL backup owner: %w",
				err,
			)
		}
		backupStageExecutor, err := gueststatebackupstageexecutor.New(
			gueststatebackupstageexecutor.Configuration{
				RootDirectory: deployment.
					GuestOperationalStateBackupRootDirectory,
				DestinationReference: deployment.
					GuestOperationalStateBackupDestinationReference,
			},
			guestRuntimeStateRepository,
			guestOperationalStateBackupOwner,
			archiveLineageRepository,
			guestruntimeapplication.SystemGuestRuntimeClock{},
		)
		if err != nil {
			_ = guestOperationalStateBackupOwner.Close()
			_ = guestOperationalStateLedger.Close()
			closeGuestRuntimeRepositories(
				guestRuntimeStateRepository,
				recorderCatalogRepository,
				archiveLineageRepository,
				recorderAssignmentRepository,
			)
			return nil, fmt.Errorf(
				"compose Guest operational-state backup stage executor: %w",
				err,
			)
		}
		var stageExecutor guestruntimeapplication.GuestOperationalStateBackupStageExecutor = backupStageExecutor
		if guestOperationalStateRestoreConfigured(deployment) {
			sqliteRestoreOwner, restoreError := gueststatesqliterestore.New(
				deployment.GuestOperationalStateRestoreSQLiteTargetPath,
			)
			if restoreError != nil {
				_ = guestOperationalStateBackupOwner.Close()
				_ = guestOperationalStateLedger.Close()
				closeGuestRuntimeRepositories(
					guestRuntimeStateRepository,
					recorderCatalogRepository,
					archiveLineageRepository,
					recorderAssignmentRepository,
				)
				return nil, fmt.Errorf(
					"compose Guest operational-state SQLite restore owner: %w",
					restoreError,
				)
			}
			guestOperationalStateRestoreOwner, restoreError =
				gueststatepostgresqlrestore.Open(
					context.Background(),
					deployment.GuestOperationalStateRestorePostgreSQLDatabaseURL,
					deployment.GuestOperationalStatePostgreSQLRestoreExecutablePath,
				)
			if restoreError != nil {
				_ = guestOperationalStateBackupOwner.Close()
				_ = guestOperationalStateLedger.Close()
				closeGuestRuntimeRepositories(
					guestRuntimeStateRepository,
					recorderCatalogRepository,
					archiveLineageRepository,
					recorderAssignmentRepository,
				)
				return nil, fmt.Errorf(
					"open Guest operational-state PostgreSQL restore owner: %w",
					restoreError,
				)
			}
			restoreStageExecutor, restoreError :=
				gueststatebackupstageexecutor.NewRestore(
					gueststatebackupstageexecutor.RestoreConfiguration{
						RootDirectory: deployment.
							GuestOperationalStateBackupRootDirectory,
						TargetReference: deployment.
							GuestOperationalStateRestoreTargetReference,
					},
					sqliteRestoreOwner,
					guestOperationalStateRestoreOwner,
					guestruntimeapplication.SystemGuestRuntimeClock{},
				)
			if restoreError != nil {
				_ = guestOperationalStateRestoreOwner.Close()
				_ = guestOperationalStateBackupOwner.Close()
				_ = guestOperationalStateLedger.Close()
				closeGuestRuntimeRepositories(
					guestRuntimeStateRepository,
					recorderCatalogRepository,
					archiveLineageRepository,
					recorderAssignmentRepository,
				)
				return nil, fmt.Errorf(
					"compose Guest operational-state restore stage executor: %w",
					restoreError,
				)
			}
			stageExecutor, restoreError = gueststatebackupstageexecutor.NewComposite(
				backupStageExecutor,
				restoreStageExecutor,
			)
			if restoreError != nil {
				_ = guestOperationalStateRestoreOwner.Close()
				_ = guestOperationalStateBackupOwner.Close()
				_ = guestOperationalStateLedger.Close()
				closeGuestRuntimeRepositories(
					guestRuntimeStateRepository,
					recorderCatalogRepository,
					archiveLineageRepository,
					recorderAssignmentRepository,
				)
				return nil, fmt.Errorf(
					"compose Guest operational-state backup and restore executor: %w",
					restoreError,
				)
			}
		}
		guestOperationalStateService, err =
			guestruntimeapplication.NewGuestOperationalStateBackupApplicationService(
				guestOperationalStateLedger,
				stageExecutor,
				guestruntimeapplication.SystemGuestRuntimeClock{},
			)
		if err != nil {
			if guestOperationalStateRestoreOwner != nil {
				_ = guestOperationalStateRestoreOwner.Close()
			}
			_ = guestOperationalStateBackupOwner.Close()
			_ = guestOperationalStateLedger.Close()
			closeGuestRuntimeRepositories(
				guestRuntimeStateRepository,
				recorderCatalogRepository,
				archiveLineageRepository,
				recorderAssignmentRepository,
			)
			return nil, fmt.Errorf(
				"compose Guest operational-state backup service: %w",
				err,
			)
		}
	}
	controlHTTPServer, err := assembleGuestRuntimeControlHTTPHandler(
		guestRuntimeStateRepository,
		recorderCatalogRepository,
		archiveLineageRepository,
		recorderAssignmentRepository,
		guestOperationalStateService,
		deployment,
	)
	if err != nil {
		if guestOperationalStateRestoreOwner != nil {
			_ = guestOperationalStateRestoreOwner.Close()
		}
		if guestOperationalStateBackupOwner != nil {
			_ = guestOperationalStateBackupOwner.Close()
		}
		if guestOperationalStateLedger != nil {
			_ = guestOperationalStateLedger.Close()
		}
		_ = recorderAssignmentRepository.Close()
		_ = archiveLineageRepository.Close()
		_ = recorderCatalogRepository.Close()
		_ = guestRuntimeStateRepository.Close()
		return nil, err
	}
	return &GuestRuntimeControlHTTPApplication{
		ControlHTTPHandler:           controlHTTPServer,
		guestRuntimeStateRepository:  guestRuntimeStateRepository,
		recorderCatalogRepository:    recorderCatalogRepository,
		archiveLineageRepository:     archiveLineageRepository,
		recorderAssignmentRepository: recorderAssignmentRepository,
		reconcileTerminalArchives:    controlHTTPServer.ReconcilePendingTerminalArchiveExports,
		runNextLabReplayEffect:       controlHTTPServer.RunNextPendingLabReplayEffect,
		guestOperationalStateLedger:  guestOperationalStateLedger,
		guestOperationalStateBackup:  guestOperationalStateBackupOwner,
		guestOperationalStateRestore: guestOperationalStateRestoreOwner,
		runNextGuestStateEffect:      controlHTTPServer.RunNextPendingGuestOperationalStateEffect,
	}, nil
}

func (controlHTTPApplication *GuestRuntimeControlHTTPApplication) startLabReplayWorker(
	parent context.Context,
) {
	workerContext, cancel := context.WithCancel(parent)
	done := make(chan struct{})
	controlHTTPApplication.stopLabReplayWorker = cancel
	controlHTTPApplication.labReplayWorkerDone = done
	go func() {
		defer close(done)
		controlHTTPApplication.runLabReplayWorker(workerContext)
	}()
}

func (controlHTTPApplication *GuestRuntimeControlHTTPApplication) runLabReplayWorker(
	ctx context.Context,
) {
	const replayTick = time.Second
	for {
		operation, ran, err := controlHTTPApplication.runNextLabReplayEffect(ctx)
		if ctx.Err() != nil {
			return
		}
		if err != nil {
			log.Printf(
				"Guest Runtime Lab replay effect outcome unresolved replayId=%s state=%s error=%v",
				operation.ID,
				operation.State,
				err,
			)
		}
		wait := time.Duration(0)
		switch {
		case err != nil || !ran:
			wait = replayTick
		case operation.State == guestruntimedomain.LabReplaySendingState &&
			operation.PreparationReceipt != nil:
			nextOutput := time.Unix(
				0,
				int64(
					(operation.PreparationReceipt.OutputStartedAt+
						float64(operation.NextFrameOffsetSecond))*float64(time.Second),
				),
			)
			wait = time.Until(nextOutput)
		case operation.State == guestruntimedomain.LabReplayAwaitingUpstreamDeliveryState:
			wait = replayTick
		}
		if wait <= 0 {
			continue
		}
		timer := time.NewTimer(wait)
		select {
		case <-ctx.Done():
			if !timer.Stop() {
				<-timer.C
			}
			return
		case <-timer.C:
		}
	}
}

func (controlHTTPApplication *GuestRuntimeControlHTTPApplication) startGuestOperationalStateWorker(
	parent context.Context,
) {
	if controlHTTPApplication.guestOperationalStateLedger == nil {
		return
	}
	workerContext, cancel := context.WithCancel(parent)
	done := make(chan struct{})
	controlHTTPApplication.stopGuestStateWorker = cancel
	controlHTTPApplication.guestStateWorkerDone = done
	go func() {
		defer close(done)
		const idleWait = time.Second
		for {
			_, ran, err := controlHTTPApplication.runNextGuestStateEffect(
				workerContext,
			)
			if workerContext.Err() != nil {
				return
			}
			if err == nil && ran {
				continue
			}
			timer := time.NewTimer(idleWait)
			select {
			case <-workerContext.Done():
				if !timer.Stop() {
					<-timer.C
				}
				return
			case <-timer.C:
			}
		}
	}()
}

// ReconcilePendingTerminalArchiveExports repeats only already-persisted Lab
// terminal Archive intents. It is a process-start recovery operation, not an
// assertion that Lab stop or Archive upload succeeded.
func (controlHTTPApplication *GuestRuntimeControlHTTPApplication) ReconcilePendingTerminalArchiveExports(ctx context.Context) error {
	if controlHTTPApplication == nil || controlHTTPApplication.reconcileTerminalArchives == nil {
		return fmt.Errorf("Guest Runtime terminal Archive reconciliation is not composed")
	}
	return controlHTTPApplication.reconcileTerminalArchives(ctx)
}

// CloseGuestRuntimeControlHTTPApplication closes the Guest Runtime state
// repository opened during composition. It does not make an operation-state
// claim about the Guest Runtime process.
func (controlHTTPApplication *GuestRuntimeControlHTTPApplication) CloseGuestRuntimeControlHTTPApplication() error {
	if controlHTTPApplication == nil ||
		controlHTTPApplication.guestRuntimeStateRepository == nil ||
		controlHTTPApplication.recorderCatalogRepository == nil ||
		controlHTTPApplication.archiveLineageRepository == nil ||
		controlHTTPApplication.recorderAssignmentRepository == nil {
		return fmt.Errorf("Guest Runtime control application does not own every opened state repository")
	}
	if controlHTTPApplication.stopLabReplayWorker != nil {
		controlHTTPApplication.stopLabReplayWorker()
	}
	if controlHTTPApplication.labReplayWorkerDone != nil {
		<-controlHTTPApplication.labReplayWorkerDone
	}
	if controlHTTPApplication.stopGuestStateWorker != nil {
		controlHTTPApplication.stopGuestStateWorker()
	}
	if controlHTTPApplication.guestStateWorkerDone != nil {
		<-controlHTTPApplication.guestStateWorkerDone
	}
	var guestOperationalStateRestoreError error
	if controlHTTPApplication.guestOperationalStateRestore != nil {
		guestOperationalStateRestoreError =
			controlHTTPApplication.guestOperationalStateRestore.Close()
	}
	var guestOperationalStateBackupError error
	if controlHTTPApplication.guestOperationalStateBackup != nil {
		guestOperationalStateBackupError =
			controlHTTPApplication.guestOperationalStateBackup.Close()
	}
	var guestOperationalStateLedgerError error
	if controlHTTPApplication.guestOperationalStateLedger != nil {
		guestOperationalStateLedgerError =
			controlHTTPApplication.guestOperationalStateLedger.Close()
	}
	assignmentError := controlHTTPApplication.recorderAssignmentRepository.Close()
	archiveError := controlHTTPApplication.archiveLineageRepository.Close()
	catalogError := controlHTTPApplication.recorderCatalogRepository.Close()
	controlLedgerError := controlHTTPApplication.guestRuntimeStateRepository.Close()
	return errors.Join(
		guestOperationalStateRestoreError,
		guestOperationalStateBackupError,
		guestOperationalStateLedgerError,
		assignmentError,
		archiveError,
		catalogError,
		controlLedgerError,
	)
}

func validateGuestRuntimeControlHTTPApplicationDeployment(deployment GuestRuntimeControlHTTPApplicationDeployment) error {
	if deployment.GuestRuntimeStateDatabasePath == "" ||
		deployment.RecorderCatalogPostgreSQLDatabaseURL == "" ||
		deployment.RecorderCatalogAdmissionBearerToken == "" ||
		deployment.ArchiveSourceAdmissionBearerToken == "" ||
		deployment.ArchiveArtifactObjectRootDirectory == "" ||
		deployment.ArchiveSourceMaximumBytes < 1 ||
		deployment.LabReplaySourceObjectRootDirectory == "" ||
		deployment.LabReplaySourceMaximumBytes < 1 ||
		deployment.LabReplaySpoolRootDirectory == "" ||
		deployment.LabReplayStringTrackPolicy == "" ||
		deployment.LabReplayGapPolicy == "" ||
		deployment.LabReplayFrameBatchSize != 1 ||
		deployment.RecorderAttributionPolicyKind == "" ||
		deployment.GuestRuntimeServiceVersion == "" ||
		deployment.GuestRuntimeInstanceID == "" {
		return fmt.Errorf("Guest Runtime state stores, Catalog and Archive admission credentials, Archive object policy, service version, and instance ID are required")
	}
	if deployment.RecorderAttributionPolicyKind != recorderassignmentresolution.RecorderAssignmentOwnerPolicyKind {
		return fmt.Errorf("Guest Runtime Recorder attribution policy kind is unsupported")
	}
	if !validGuestOperationalStateBackupConfiguration(deployment) {
		return fmt.Errorf(
			"Guest operational-state backup configuration must be either absent or complete",
		)
	}
	if !validGuestOperationalStateRestoreConfiguration(deployment) {
		return fmt.Errorf(
			"Guest operational-state restore configuration must be absent or a complete empty-target configuration attached to backup",
		)
	}
	if !filepath.IsAbs(deployment.LabReplaySourceObjectRootDirectory) ||
		!filepath.IsAbs(deployment.LabReplaySpoolRootDirectory) {
		return fmt.Errorf("Guest Runtime Lab replay source and spool root directories must be absolute")
	}
	if deployment.LabReplayStringTrackPolicy != guestruntimedomain.VitalFileStringTrackPolicyReject &&
		deployment.LabReplayStringTrackPolicy != guestruntimedomain.VitalFileStringTrackPolicySkip {
		return fmt.Errorf("Guest Runtime Lab replay string-track policy is unsupported")
	}
	if !guestruntimedomain.ValidVitalFileReplayGapPolicy(deployment.LabReplayGapPolicy) {
		return fmt.Errorf("Guest Runtime Lab replay gap policy is unsupported")
	}
	if err := guestruntimedomain.ValidateRecorderObservationFreshnessPolicy(guestruntimedomain.RecorderObservationFreshnessPolicy{MaxReportAgeSeconds: deployment.RecorderObservationMaxReportAgeSeconds}); err != nil {
		return err
	}
	if deployment.GuestRuntimeNode.Kind == "" || deployment.GuestRuntimeNode.ID == "" || deployment.GuestTimeAuthorityID == "" {
		return fmt.Errorf("Guest Runtime node and Time Authority ID are required")
	}
	if deployment.RecorderGatewayColdPathSourceEndpoint == "" || deployment.LabRecorderRunnerEndpoint == "" || deployment.OutboundRelayObservationProviderOutcomeMode == "" {
		return fmt.Errorf("Guest Runtime selected provider outcome modes are required")
	}
	if err := validateGuestRuntimeTimeAuthorityAdapter(deployment); err != nil {
		return err
	}
	if err := validateGuestRuntimeTelemetryAdapter(deployment); err != nil {
		return err
	}
	if deployment.ArchiveExportProviderReference.CapabilityRevision < 1 || deployment.ExternalUpstreamObservationProviderReference.CapabilityRevision < 1 || deployment.OutboundRelayObservationProviderReference.CapabilityRevision < 1 {
		return fmt.Errorf("Guest Runtime selected provider capability revisions must be at least one")
	}
	switch deployment.ArchiveExportProviderReference.Kind {
	case "archive-export-outcome-profile":
		if deployment.ArchiveExportProviderOutcomeMode == "" || deployment.ArchiveProviderVitalServerConfigurationKind != "" || deployment.ArchiveProviderVitalServerConfigurationPath != "" || deployment.ArchiveProviderCredentialMaterialPath != "" {
			return fmt.Errorf("Guest Runtime Archive outcome profile must provide only its explicit outcome mode")
		}
	case "vitalserver-indexed-library":
		if deployment.ArchiveExportProviderOutcomeMode != "" || !validArchiveProviderVitalServerConfigurationKind(deployment.ArchiveProviderVitalServerConfigurationKind) || deployment.ArchiveProviderVitalServerConfigurationPath == "" || deployment.ArchiveProviderCredentialMaterialPath == "" {
			return fmt.Errorf("Guest Runtime VitalServer indexed-library provider requires explicit C44-or-C46 configuration kind, configuration path, and credential material path")
		}
	default:
		return fmt.Errorf("Guest Runtime Archive provider kind is unsupported")
	}
	if err := validateGuestRuntimeExternalUpstreamObservationProvider(deployment); err != nil {
		return err
	}
	return nil
}

func assembleGuestRuntimeControlHTTPHandler(
	guestRuntimeStateRepository *gueststatesqliterepository.GuestRuntimeStateSQLiteRepository,
	recorderCatalogRepository recorderCatalogRepository,
	archiveLineageRepository archiveLineageRepository,
	recorderAssignmentRepository recorderAssignmentRepository,
	guestOperationalStateService *guestruntimeapplication.GuestOperationalStateBackupApplicationService,
	deployment GuestRuntimeControlHTTPApplicationDeployment,
) (*guestruntimecontrolhttpapi.GuestRuntimeControlHTTPServer, error) {
	guestRuntimeApplicationClock := guestruntimeapplication.SystemGuestRuntimeClock{}
	guestBootstrapIdentityReader, err := guestbootstrapidentityfile.NewReader(
		guestbootstrapidentityfile.Configuration{
			MigrationReceiptPath:                          deployment.RecorderCatalogMigrationReceiptPath,
			RecorderCatalogDatabaseURLMaterialPath:        deployment.RecorderCatalogDatabaseURLMaterialPath,
			CatalogAdmissionBearerTokenMaterialPath:       deployment.RecorderCatalogAdmissionBearerTokenMaterialPath,
			ArchiveSourceAdmissionBearerTokenMaterialPath: deployment.ArchiveSourceAdmissionBearerTokenMaterialPath,
		},
	)
	if err != nil {
		return nil, fmt.Errorf(
			"compose Guest bootstrap identity reader: %w",
			err,
		)
	}
	guestOperationalStateIdentityService, err :=
		guestruntimeapplication.NewGuestOperationalStateIdentityApplicationService(
			guestRuntimeStateRepository,
			recorderCatalogRepository,
			guestBootstrapIdentityReader,
			guestRuntimeApplicationClock,
		)
	if err != nil {
		return nil, fmt.Errorf(
			"compose Guest operational-state identity service: %w",
			err,
		)
	}
	externalUpstreamObservationProvider, err := composeGuestRuntimeExternalUpstreamObservationProvider(deployment)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime External Upstream provider: %w", err)
	}
	externalUpstreamService, err := guestruntimeapplication.NewGuestRuntimeExternalUpstreamApplicationService(
		guestRuntimeStateRepository,
		externalUpstreamObservationProvider,
		guestRuntimeApplicationClock,
		guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{},
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime External Upstream service: %w", err)
	}

	// Relay uses its own configured observation profile because its persistent
	// resource owner and observation lifecycle are distinct from External
	// Upstream.
	outboundRelayObservationProvider, err := outboundrelayobservationprovider.NewConfiguredOutboundRelayObservationProfile(
		deployment.OutboundRelayObservationProviderReference,
		deployment.OutboundRelayObservationProviderOutcomeMode,
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Outbound Relay provider: %w", err)
	}
	outboundRelayService, err := guestruntimeapplication.NewGuestRuntimeOutboundRelayApplicationService(
		guestRuntimeStateRepository,
		outboundRelayObservationProvider,
		guestRuntimeApplicationClock,
		guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{},
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Outbound Relay service: %w", err)
	}

	topologyService, err := guestruntimeapplication.NewGuestRuntimeTopologyApplicationServiceWithDependencies(
		guestRuntimeStateRepository,
		externalUpstreamService,
		[]guestruntimeapplication.GuestRuntimeReadinessDependency{
			recorderCatalogRepository,
			archiveLineageRepository,
			recorderAssignmentRepository,
		},
		guestRuntimeApplicationClock,
		guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{},
		deployment.GuestRuntimeServiceVersion,
		deployment.GuestRuntimeInstanceID,
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime topology service: %w", err)
	}
	labRecorderRunner, err := labrecorderrunner.NewLabRecorderRunnerHTTPClient(deployment.LabRecorderRunnerEndpoint)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Lab recorder Runner client: %w", err)
	}
	labService, err := guestruntimeapplication.NewGuestRuntimeLabApplicationServiceWithRecorderRunner(
		guestRuntimeStateRepository,
		labRecorderRunner,
		guestRuntimeApplicationClock,
		guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{},
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Lab service: %w", err)
	}
	archiveCredentialMaterialOwner, err := composeGuestRuntimeArchiveCredentialMaterialOwner(deployment)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Archive credential-material owner: %w", err)
	}
	var archiveCredentialMaterialService *guestruntimeapplication.GuestRuntimeArchiveCredentialMaterialApplicationService
	if archiveCredentialMaterialOwner != nil {
		archiveCredentialMaterialService, err = guestruntimeapplication.NewGuestRuntimeArchiveCredentialMaterialApplicationService(
			archiveCredentialMaterialOwner,
			guestRuntimeApplicationClock,
		)
		if err != nil {
			return nil, fmt.Errorf("compose Guest Runtime Archive credential-material service: %w", err)
		}
	}
	archiveExportProvider, err := composeGuestRuntimeArchiveExportProvider(deployment)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Archive provider: %w", err)
	}
	recorderGatewayColdPathSourceReader, err := recordergatewaycoldpathsource.NewRecorderGatewayColdPathHTTPSourceReader(
		deployment.RecorderGatewayColdPathSourceEndpoint,
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Recorder Gateway cold-path source reader: %w", err)
	}
	vitalArtifactFormationProvider := vitalartifactformation.NewRecorderColdPathVitalArtifactFormationProvider()
	archiveService, err := guestruntimeapplication.NewGuestRuntimeArchiveApplicationService(
		guestRuntimeStateRepository,
		labService,
		recorderGatewayColdPathSourceReader,
		vitalArtifactFormationProvider,
		archiveExportProvider,
		guestRuntimeApplicationClock,
		guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{},
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Archive service: %w", err)
	}
	archiveLineageService, err := guestruntimeapplication.NewGuestRuntimeArchiveLineageApplicationService(
		archiveLineageRepository,
		guestRuntimeApplicationClock,
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Archive lineage service: %w", err)
	}
	archiveArtifactObjectStore, err := archiveartifactobjectfile.OpenFileArchiveArtifactObjectStore(
		deployment.ArchiveArtifactObjectRootDirectory,
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Archive artifact object store: %w", err)
	}
	recorderAssignmentService, err := guestruntimeapplication.NewGuestRuntimeRecorderAssignmentApplicationService(
		recorderAssignmentRepository,
		guestRuntimeApplicationClock,
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Recorder assignment service: %w", err)
	}
	recorderAttributionResolver, err := recorderassignmentresolution.NewRecorderAssignmentOwnerAttributionResolver(
		recorderAssignmentService,
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Recorder attribution resolver: %w", err)
	}
	archiveSourceAdmissionService, err := guestruntimeapplication.NewGuestRuntimeArchiveSourceAdmissionApplicationService(
		archiveLineageRepository,
		archiveArtifactObjectStore,
		recorderAttributionResolver,
		guestRuntimeApplicationClock,
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Archive source admission service: %w", err)
	}
	labReplaySourceObjectStore, err := labreplaysourcefile.OpenFileLabReplaySourceObjectStore(
		deployment.LabReplaySourceObjectRootDirectory,
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Lab replay source object store: %w", err)
	}
	labReplaySourceService, err := guestruntimeapplication.NewGuestRuntimeLabReplaySourceApplicationService(
		guestRuntimeStateRepository,
		labReplaySourceObjectStore,
		guestRuntimeApplicationClock,
		deployment.LabReplaySourceMaximumBytes,
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Lab replay source service: %w", err)
	}
	labReplayParser, err := vitalfilereplayparser.NewVitalFileReplayParser(
		guestruntimedomain.VitalFileReplayCompatibilityPolicy{
			StringTrackPolicy: deployment.LabReplayStringTrackPolicy,
		},
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Lab replay parser: %w", err)
	}
	labReplaySpoolFactory, err := vitalfilereplayspoolsqlite.NewFactory(
		deployment.LabReplaySpoolRootDirectory,
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Lab replay spool factory: %w", err)
	}
	labReplayService, err := guestruntimeapplication.NewGuestRuntimeLabReplayApplicationService(
		guestRuntimeStateRepository,
		labReplaySourceObjectStore,
		labReplayParser,
		labReplaySpoolFactory,
		labRecorderRunner,
		deployment.LabReplayFrameBatchSize,
		deployment.LabReplayGapPolicy,
		guestRuntimeApplicationClock,
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Lab replay service: %w", err)
	}
	guestTimeAuthorityProvider, err := composeGuestRuntimeTimeAuthorityProvider(deployment)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Time Authority provider: %w", err)
	}
	guestTimeAuthorityService, err := guestruntimeapplication.NewGuestRuntimeTimeAuthorityApplicationService(
		guestRuntimeStateRepository,
		guestTimeAuthorityProvider,
		guestRuntimeApplicationClock,
		guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{},
		deployment.GuestRuntimeNode,
		deployment.GuestTimeAuthorityID,
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Time Authority service: %w", err)
	}
	recorderObservationCatalogService, err := guestruntimeapplication.NewGuestRuntimeObservationCatalogApplicationService(
		recorderCatalogRepository,
		guestRuntimeApplicationClock,
		guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{},
		guestruntimedomain.RecorderObservationFreshnessPolicy{MaxReportAgeSeconds: deployment.RecorderObservationMaxReportAgeSeconds},
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Recorder Observation Catalog service: %w", err)
	}
	guestTelemetryExporter, err := composeGuestRuntimeTelemetryExporter(deployment)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Telemetry exporter: %w", err)
	}
	guestTelemetryPipelineService, err := guestruntimeapplication.NewGuestRuntimeTelemetryPipelineApplicationService(
		guestRuntimeStateRepository,
		guestTelemetryExporter,
		guestRuntimeApplicationClock,
		guestruntimeapplication.CryptoGuestRuntimeRequestCorrelationIdentifierGenerator{},
		deployment.GuestRuntimeNode,
	)
	if err != nil {
		return nil, fmt.Errorf("compose Guest Runtime Telemetry Pipeline service: %w", err)
	}
	return guestruntimecontrolhttpapi.NewGuestRuntimeControlHTTPServerWithModules(guestruntimecontrolhttpapi.GuestRuntimeControlModules{
		Topology:                          topologyService,
		Lab:                               labService,
		Archive:                           archiveService,
		ArchiveLineage:                    archiveLineageService,
		ArchiveSourceAdmission:            archiveSourceAdmissionService,
		ArchiveSourceAdmissionBearerToken: deployment.ArchiveSourceAdmissionBearerToken,
		ArchiveSourceMaximumBytes:         deployment.ArchiveSourceMaximumBytes,
		LabReplaySource:                   labReplaySourceService,
		LabReplaySourceMaximumBytes:       deployment.LabReplaySourceMaximumBytes,
		LabReplay:                         labReplayService,
		ArchiveCredentialMaterial:         archiveCredentialMaterialService,
		ExternalUpstreamIntegration:       externalUpstreamService,
		OutboundRelayTarget:               outboundRelayService,
		GuestTimeAuthority:                guestTimeAuthorityService,
		RecorderObservationCatalog:        recorderObservationCatalogService,
		RecorderObservationCatalogAdmissionBearerToken: deployment.RecorderCatalogAdmissionBearerToken,
		RecorderAssignment:            recorderAssignmentService,
		GuestOperationalStateIdentity: guestOperationalStateIdentityService,
		GuestOperationalStateBackup:   guestOperationalStateService,
		GuestOperationalStateRestoreAdmissionEnabled: guestOperationalStateRestoreConfigured(
			deployment,
		),
		GuestTelemetryPipeline:               guestTelemetryPipelineService,
		LabArchiveLifecycleCoordinationClock: guestRuntimeApplicationClock,
	}), nil
}

func guestOperationalStateBackupConfigured(
	deployment GuestRuntimeControlHTTPApplicationDeployment,
) bool {
	return deployment.GuestOperationalStateBackupRootDirectory != ""
}

func guestOperationalStateRestoreConfigured(
	deployment GuestRuntimeControlHTTPApplicationDeployment,
) bool {
	return deployment.GuestOperationalStateRestoreSQLiteTargetPath != ""
}

func validGuestOperationalStateBackupConfiguration(
	deployment GuestRuntimeControlHTTPApplicationDeployment,
) bool {
	valuesPresent := []bool{
		deployment.GuestOperationalStateBackupRootDirectory != "",
		deployment.GuestOperationalStateBackupLedgerDatabasePath != "",
		deployment.GuestOperationalStateBackupDestinationReference.ResourceType != "",
		deployment.GuestOperationalStateBackupDestinationReference.ResourceID != "",
		deployment.GuestOperationalStatePostgreSQLDumpExecutablePath != "",
		deployment.GuestOperationalStatePostgreSQLRestoreExecutablePath != "",
	}
	present := 0
	for _, valuePresent := range valuesPresent {
		if valuePresent {
			present++
		}
	}
	if present == 0 {
		return true
	}
	if present != len(valuesPresent) {
		return false
	}
	return filepath.IsAbs(
		deployment.GuestOperationalStateBackupRootDirectory,
	) &&
		filepath.IsAbs(
			deployment.GuestOperationalStateBackupLedgerDatabasePath,
		) &&
		filepath.IsAbs(
			deployment.GuestOperationalStatePostgreSQLDumpExecutablePath,
		) &&
		filepath.IsAbs(
			deployment.GuestOperationalStatePostgreSQLRestoreExecutablePath,
		) &&
		guestruntimedomain.ValidIdentifier(
			deployment.GuestOperationalStateBackupDestinationReference.ResourceType,
		) &&
		guestruntimedomain.ValidIdentifier(
			deployment.GuestOperationalStateBackupDestinationReference.ResourceID,
		)
}

func validGuestOperationalStateRestoreConfiguration(
	deployment GuestRuntimeControlHTTPApplicationDeployment,
) bool {
	valuesPresent := []bool{
		deployment.GuestOperationalStateRestoreTargetReference.ResourceType != "",
		deployment.GuestOperationalStateRestoreTargetReference.ResourceID != "",
		deployment.GuestOperationalStateRestoreSQLiteTargetPath != "",
		deployment.GuestOperationalStateRestorePostgreSQLDatabaseURL != "",
	}
	present := 0
	for _, valuePresent := range valuesPresent {
		if valuePresent {
			present++
		}
	}
	if present == 0 {
		return true
	}
	if present != len(valuesPresent) ||
		!guestOperationalStateBackupConfigured(deployment) {
		return false
	}
	return filepath.IsAbs(
		deployment.GuestOperationalStateRestoreSQLiteTargetPath,
	) &&
		deployment.GuestOperationalStateRestoreSQLiteTargetPath !=
			deployment.GuestRuntimeStateDatabasePath &&
		deployment.GuestOperationalStateRestorePostgreSQLDatabaseURL !=
			deployment.RecorderCatalogPostgreSQLDatabaseURL &&
		guestruntimedomain.ValidIdentifier(
			deployment.GuestOperationalStateRestoreTargetReference.ResourceType,
		) &&
		guestruntimedomain.ValidIdentifier(
			deployment.GuestOperationalStateRestoreTargetReference.ResourceID,
		)
}

func closeGuestRuntimeRepositories(
	guestRuntimeStateRepository *gueststatesqliterepository.GuestRuntimeStateSQLiteRepository,
	recorderCatalogRepository recorderCatalogRepository,
	archiveLineageRepository archiveLineageRepository,
	recorderAssignmentRepository recorderAssignmentRepository,
) {
	_ = recorderAssignmentRepository.Close()
	_ = archiveLineageRepository.Close()
	_ = recorderCatalogRepository.Close()
	_ = guestRuntimeStateRepository.Close()
}

func validateGuestRuntimeExternalUpstreamObservationProvider(deployment GuestRuntimeControlHTTPApplicationDeployment) error {
	switch deployment.ExternalUpstreamObservationProviderReference.Kind {
	case "external-capability-profile":
		if deployment.ExternalUpstreamObservationProviderOutcomeMode == "" || deployment.ExternalUpstreamObservationExternalVitalServerDeliveryConfigurationPath != "" || deployment.ExternalUpstreamObservationRequestTimeoutMilliseconds != 0 {
			return fmt.Errorf("Guest Runtime External Upstream outcome profile requires only an explicit outcome mode")
		}
	case "external-vitalserver-http":
		if deployment.ExternalUpstreamObservationProviderOutcomeMode != "" || deployment.ExternalUpstreamObservationExternalVitalServerDeliveryConfigurationPath == "" || deployment.ExternalUpstreamObservationRequestTimeoutMilliseconds < 1 || deployment.ExternalUpstreamObservationRequestTimeoutMilliseconds > 60000 {
			return fmt.Errorf("Guest Runtime External VitalServer HTTP observation provider requires C46 configuration path and request timeout")
		}
	default:
		return fmt.Errorf("Guest Runtime External Upstream observation provider kind is unsupported")
	}
	return nil
}

func composeGuestRuntimeExternalUpstreamObservationProvider(deployment GuestRuntimeControlHTTPApplicationDeployment) (guestruntimeapplication.GuestRuntimeExternalUpstreamProvider, error) {
	switch deployment.ExternalUpstreamObservationProviderReference.Kind {
	case "external-capability-profile":
		return externalupstreamobservationprovider.NewConfiguredExternalUpstreamObservationProfile(
			deployment.ExternalUpstreamObservationProviderReference,
			deployment.ExternalUpstreamObservationProviderOutcomeMode,
		)
	case "external-vitalserver-http":
		return externalupstreamobservationprovider.NewExternalVitalServerHTTPObservationProviderFromFile(
			deployment.ExternalUpstreamObservationProviderReference,
			deployment.ExternalUpstreamObservationExternalVitalServerDeliveryConfigurationPath,
			time.Duration(deployment.ExternalUpstreamObservationRequestTimeoutMilliseconds)*time.Millisecond,
		)
	default:
		return nil, fmt.Errorf("Guest Runtime External Upstream observation provider kind is unsupported")
	}
}

func validateGuestRuntimeTimeAuthorityAdapter(deployment GuestRuntimeControlHTTPApplicationDeployment) error {
	switch deployment.GuestTimeAuthorityAdapterKind {
	case "time-authority-outcome-profile":
		if deployment.GuestTimeAuthorityChronyExecutablePath != "" || deployment.GuestTimeAuthorityRequestTimeoutMilliseconds != 0 || deployment.GuestTimeAuthorityProbeOutcomeMode == "" {
			return fmt.Errorf("Guest Runtime Time Authority outcome profile requires only an explicit probe outcome mode")
		}
	case "chrony-tracking":
		if deployment.GuestTimeAuthorityProbeOutcomeMode != "" || deployment.GuestTimeAuthorityChronyExecutablePath == "" || deployment.GuestTimeAuthorityRequestTimeoutMilliseconds < 1 || deployment.GuestTimeAuthorityRequestTimeoutMilliseconds > 60000 {
			return fmt.Errorf("Guest Runtime Chrony Time Authority adapter requires only an explicit executable path and request timeout")
		}
		if _, err := timeprovider.NewChronyTrackingTimeAuthorityProvider(deployment.GuestTimeAuthorityChronyExecutablePath, time.Duration(deployment.GuestTimeAuthorityRequestTimeoutMilliseconds)*time.Millisecond); err != nil {
			return fmt.Errorf("Guest Runtime Chrony Time Authority adapter configuration is invalid: %w", err)
		}
	default:
		return fmt.Errorf("Guest Runtime Time Authority adapter kind is unsupported")
	}
	return nil
}

func composeGuestRuntimeTimeAuthorityProvider(deployment GuestRuntimeControlHTTPApplicationDeployment) (guestruntimeapplication.GuestRuntimeTimeAuthorityProvider, error) {
	switch deployment.GuestTimeAuthorityAdapterKind {
	case "time-authority-outcome-profile":
		return timeprovider.NewConfiguredTimeAuthorityOutcomeProfile(deployment.GuestTimeAuthorityProbeOutcomeMode)
	case "chrony-tracking":
		return timeprovider.NewChronyTrackingTimeAuthorityProvider(deployment.GuestTimeAuthorityChronyExecutablePath, time.Duration(deployment.GuestTimeAuthorityRequestTimeoutMilliseconds)*time.Millisecond)
	default:
		return nil, fmt.Errorf("Guest Runtime Time Authority adapter kind is unsupported")
	}
}

func validateGuestRuntimeTelemetryAdapter(deployment GuestRuntimeControlHTTPApplicationDeployment) error {
	switch deployment.GuestTelemetryAdapterKind {
	case "telemetry-export-outcome-profile":
		if deployment.GuestTelemetryCollectorBaseEndpoint != "" || deployment.GuestTelemetryRequestTimeoutMilliseconds != 0 || deployment.GuestTelemetryCollectorProbeOutcomeMode == "" || deployment.GuestTelemetryExportOutcomeMode == "" {
			return fmt.Errorf("Guest Runtime telemetry outcome profile requires only explicit pipeline and export outcome modes")
		}
	case "otlp-http":
		if deployment.GuestTelemetryCollectorProbeOutcomeMode != "" || deployment.GuestTelemetryExportOutcomeMode != "" || deployment.GuestTelemetryCollectorBaseEndpoint == "" || deployment.GuestTelemetryRequestTimeoutMilliseconds < 1 || deployment.GuestTelemetryRequestTimeoutMilliseconds > 60000 {
			return fmt.Errorf("Guest Runtime OTLP HTTP telemetry adapter requires only an explicit Collector base endpoint and request timeout")
		}
		if _, err := telemetryexporter.NewOTLPHTTPTelemetryExporter(deployment.GuestTelemetryCollectorBaseEndpoint, time.Duration(deployment.GuestTelemetryRequestTimeoutMilliseconds)*time.Millisecond); err != nil {
			return fmt.Errorf("Guest Runtime OTLP HTTP telemetry adapter configuration is invalid: %w", err)
		}
	default:
		return fmt.Errorf("Guest Runtime telemetry adapter kind is unsupported")
	}
	return nil
}

func composeGuestRuntimeTelemetryExporter(deployment GuestRuntimeControlHTTPApplicationDeployment) (guestruntimeapplication.GuestRuntimeTelemetryExporter, error) {
	switch deployment.GuestTelemetryAdapterKind {
	case "telemetry-export-outcome-profile":
		return telemetryexporter.NewConfiguredTelemetryExportOutcomeProfile(deployment.GuestTelemetryCollectorProbeOutcomeMode, deployment.GuestTelemetryExportOutcomeMode)
	case "otlp-http":
		return telemetryexporter.NewOTLPHTTPTelemetryExporter(deployment.GuestTelemetryCollectorBaseEndpoint, time.Duration(deployment.GuestTelemetryRequestTimeoutMilliseconds)*time.Millisecond)
	default:
		return nil, fmt.Errorf("Guest Runtime telemetry adapter kind is unsupported")
	}
}

func composeGuestRuntimeArchiveExportProvider(deployment GuestRuntimeControlHTTPApplicationDeployment) (guestruntimeapplication.GuestRuntimeArchiveExportProvider, error) {
	switch deployment.ArchiveExportProviderReference.Kind {
	case "archive-export-outcome-profile":
		provider, err := archiveprovider.NewConfiguredArchiveExportOutcomeProfile(
			deployment.ArchiveExportProviderReference,
			deployment.ArchiveExportProviderOutcomeMode,
		)
		if err != nil {
			return nil, err
		}
		return provider, nil
	case "vitalserver-indexed-library":
		return vitalserverindexedlibrary.NewDeferredVitalServerIndexedLibraryHTTPArchiveExportProvider(
			deployment.ArchiveProviderVitalServerConfigurationKind,
			deployment.ArchiveProviderVitalServerConfigurationPath,
			deployment.ArchiveProviderCredentialMaterialPath,
			deployment.ArchiveExportProviderReference,
		), nil
	default:
		return nil, fmt.Errorf("Guest Runtime Archive provider kind is unsupported")
	}
}

func composeGuestRuntimeArchiveCredentialMaterialOwner(deployment GuestRuntimeControlHTTPApplicationDeployment) (guestruntimeapplication.GuestRuntimeArchiveCredentialMaterialOwner, error) {
	if deployment.ArchiveExportProviderReference.Kind != "vitalserver-indexed-library" {
		return nil, nil
	}
	return vitalserverindexedlibrary.NewVitalServerIndexedLibraryCredentialMaterialFileOwner(
		deployment.ArchiveProviderVitalServerConfigurationKind,
		deployment.ArchiveProviderVitalServerConfigurationPath,
		deployment.ArchiveProviderCredentialMaterialPath,
		deployment.ArchiveExportProviderReference,
	)
}

func validArchiveProviderVitalServerConfigurationKind(kind string) bool {
	return kind == vitalserverindexedlibrary.ExternalVitalServerDeliveryConfigurationKind || kind == vitalserverindexedlibrary.BundledVitalServerTopologyDeploymentKind
}
