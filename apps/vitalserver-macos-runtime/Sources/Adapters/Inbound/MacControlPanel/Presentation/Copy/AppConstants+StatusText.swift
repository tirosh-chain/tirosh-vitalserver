import Foundation
import Contracts
import Errors

public extension AppConstants {
    enum StatusText {
        public static let ready = "Ready"
        public static let vitalServerUnavailable = "VitalServer is unavailable"
        public static let vitalServerNeedsAttention = "VitalServer needs attention"
        public static let runtimeNotInstalled = "Runtime is not installed"
        public static let noRuntimeEvents = "No runtime events"
        public static let allRuntimeEvents = "All events"
        public static let noVitalRecorderData = "No Vital Recorder data"
        public static let noBedData = "No bed data"
        public static let selectBed = "Select a bed to view details."
        public static let noRecorderAnomalies = "No recorder anomalies"
        public static let unavailable = "Unavailable"
        public static let healthy = "Healthy"
        public static let unhealthy = "Unhealthy"
        public static let starting = "Starting"
        public static let installing = "Installing"
        public static let initializing = "Initializing"
        public static let updating = "Updating"
        public static let recovering = "Recovering"
        public static let degraded = "Degraded"
        public static let needsAttention = "Needs attention"
        public static let critical = "Critical"
        public static let running = "Running"
        public static let stopped = "Stopped"
        public static let disabled = "Disabled"
        public static let reachable = "Reachable"
        public static let unreachable = "Unreachable"
        public static let installed = "Installed"
        public static let notInstalled = "Not Installed"
        public static let waiting = "Waiting"
        public static let guestStateStale = "Guest state stale"
        public static let notChecked = "Not checked"
        public static let planned = "Planned"
        public static let notAvailable = "Not Available"
        public static let noLogData = "No log data for this source yet."
        public static let unknown = "Unknown"
        public static let notReported = "Not reported"
        public static let notReady = "Not ready"
        public static let online = "Online"
        public static let offline = "Offline"
        public static let stale = "Stale"
        public static let failed = "Failed"
        public static let skipped = "Skipped"
        public static let done = "Done"
        public static let actionUnavailable = "This action is not available for the current runtime connection."
        public static let healthCheckCompleted = "Health check completed"
        public static let missingUninstaller = "Missing uninstaller"
        public static let uninstallPreparing = "Preparing runtime removal..."
        public static let uninstallWaitingForPrivilege = "Waiting for administrator approval..."
        public static let uninstallRunning = "Starting background uninstaller..."
        public static let uninstallCompleted = "Background uninstaller started."
        public static let cleanUninstallCompleted = "Background clean uninstaller started."
        public static let applicationWillQuit = "The Helper app will quit now. Cleanup continues in the background."
        public static let proxyRepairPreparing = "Preparing host proxy repair..."
        public static let proxyRepairRunning = "Repairing host proxy..."
        public static let proxyRepairCompleted = "Host proxy repair completed."
        public static let datastoreRepairPreparing = "Preparing data store repair..."
        public static let datastoreRepairRunning = "Repairing data store..."
        public static let datastoreRepairCompleted = "Data store repair completed."
        public static let vmDiskRepairPreparing = "Preparing VM disk repair..."
        public static let vmDiskRepairRunning = "Recreating VM disk..."
        public static let vmDiskRepairCompleted = "VM disk repair completed."
        public static let runtimeServicesRepairPreparing = "Preparing runtime services repair..."
        public static let runtimeServicesRepairRunning = "Restarting runtime services..."
        public static let runtimeServicesRepaired = "Runtime services repaired."
        public static let logExportPreparing = "Preparing log export..."
        public static let logExportCompleted = "Logs exported."
        public static let logExportFailed = "Log export failed."
        public static let logExportUnavailable = "Log export is not available for this runtime connection."
        public static let logExportDestinationInvalid = "Choose a local zip file destination for log export."
        public static let logExportDestinationDirectory = "Choose a zip file destination, not a folder."
        public static let logExportDestinationNotWritable = "The selected folder is not writable. Choose another local folder for log export."
        public static let logExportDestinationProtected = "Choose a local folder that the Helper can write to. iCloud Drive, Desktop, Documents, system, and app-managed folders are not supported for log export."
        public static func logExportDestinationInspectionFailed(_ message: String) -> String {
            "Could not inspect log export destination: \(message)"
        }
        public static let restartVMRuntimePreparing = "Preparing VM runtime restart..."
        public static let restartVMRuntimeRunning = "Restarting VM runtime..."
        public static let restartVMRuntimeCompleted = "VM runtime restarted."
        public static let settingsApplyPreparing = "Preparing runtime settings..."
        public static let settingsApplyRunning = "Applying runtime settings..."
        public static let settingsApplied = "Runtime settings applied."
        public static let runtimeControlReconnecting = "Reconnecting Runtime Control and relaunching VitalServer Helper..."
        public static let applySettingsConfirmation = "Apply these settings to the installed runtime?\n\nThis may update launchd services, rewrite runtime configuration, reconcile Guest stack when required, and restart the VM runtime only when a changed setting requires it and activation after save is enabled."
        public static let restartVMRuntimeConfirmation = "Restart the VM runtime now?\n\nVitalServer may be briefly unavailable. Saved VM settings that are waiting for restart become active after the runtime starts again."
        public static let noRuntimeActivationRequired = "No runtime activation required for these changes."
        public static let noVMRuntimeRestartRequired = noRuntimeActivationRequired
        public static func vmRuntimeWillRestartAfterSave(requiredBy: String) -> String {
            "The VM runtime will restart after save. Required by: \(requiredBy)."
        }
        public static func vmRuntimeRestartRequiredButDisabled(requiredBy: String) -> String {
            "Saved changes will not become active until the VM runtime restarts. Required by: \(requiredBy)."
        }
        public static func guestStackWillReconcileAfterSave(requiredBy: String) -> String {
            "Guest stack will be reconciled after save. Required by: \(requiredBy)."
        }
        public static func guestStackReconcileRequiredButDisabled(requiredBy: String) -> String {
            "Saved changes will not become active until the Guest stack is reconciled. Required by: \(requiredBy)."
        }
        public static let updateBundleApplied = "Update bundle applied."
        public static let updateBundleAppliedRelaunching = "Update bundle applied. Relaunching VitalServer Helper..."
        public static let updateBundlePreparing = "Preparing update bundle..."
        public static let updateBundleApplying = "Applying update bundle..."
        public static let updateBundleVerifying = "Verifying update bundle..."
        public static let updateBundleVerified = "Update bundle verified."
        public static let updateBundleVerificationFailed = "Update bundle verification failed."
        public static let updateBundleNotVerified = "Verify the update bundle before applying it."
        public static let updateBundleConfirmation = "Apply this verified bundle?\n\nThis may restart VitalServer services. Detailed progress is written to the Command log and Update activation log."
        public static let rollbackCompleted = "Rollback completed."
        public static let rollbackPreparing = "Preparing rollback..."
        public static let rollbackRunning = "Rolling back runtime..."
        public static let backupDeleted = "Update backup deleted."
        public static let backupDeletePreparing = "Preparing update backup deletion..."
        public static let backupDeleteRunning = "Deleting update backup..."
        public static let runtimeDataBackupDeleted = "VitalServer backup deleted."
        public static let runtimeDataBackupDeletePreparing = "Preparing VitalServer backup deletion..."
        public static let runtimeDataBackupDeleteRunning = "Deleting VitalServer backup..."
        public static let redisBackupPreparing = "Preparing Redis-only backup..."
        public static let redisBackupRunning = "Creating Redis-only backup..."
        public static let redisBackupCompleted = "Redis-only backup completed."
        public static let redisBackupImportPreparing = "Preparing Redis-only backup import..."
        public static let redisBackupImportRunning = "Importing Redis-only backup..."
        public static let redisBackupImported = "Redis-only backup imported."
        public static let redisBackupImportSourceInvalid = "Choose a Redis-only backup archive to import."
        public static let redisBackupImportDestinationExists = "A Redis-only backup with this file name already exists."
        public static func redisBackupImportFailed(_ message: String) -> String {
            "Could not import Redis-only backup: \(message)"
        }
        public static func redisBackupImportPathInvalid(_ state: String) -> String {
            "Could not import Redis-only backup because the backup path state is \(state)."
        }
        public static func redisBackupImportSourcePathInvalid(_ state: String) -> String {
            "Could not import Redis-only backup because the selected path state is \(state)."
        }
        public static let redisRestorePreparing = "Preparing Redis-only restore..."
        public static let redisRestoreRunning = "Restoring Redis-only backup..."
        public static let redisRestoreCompleted = "Redis-only restore completed."
        public static let runtimeDataBackupPreparing = "Preparing VitalServer backup..."
        public static let runtimeDataBackupRunning = "Creating VitalServer backup..."
        public static let runtimeDataBackupCompleted = "VitalServer backup completed."
        public static let runtimeDataBackupImportPreparing = "Preparing VitalServer backup import..."
        public static let runtimeDataBackupImportRunning = "Importing VitalServer backup..."
        public static let runtimeDataBackupImported = "VitalServer backup imported."
        public static let runtimeDataBackupImportSourceInvalid = "Choose a VitalServer backup folder to import."
        public static let runtimeDataBackupImportDestinationExists = "A VitalServer backup with this folder name already exists."
        public static func runtimeDataBackupImportFailed(_ message: String) -> String {
            "Could not import VitalServer backup: \(message)"
        }
        public static func runtimeDataBackupImportPathInvalid(_ state: String) -> String {
            "Could not import VitalServer backup because the backup folder path state is \(state)."
        }
        public static func runtimeDataBackupImportSourcePathInvalid(_ state: String) -> String {
            "Could not import VitalServer backup because the selected path state is \(state)."
        }
        public static let runtimeDataRestorePreparing = "Preparing VitalServer restore..."
        public static let runtimeDataRestoreRunning = "Restoring VitalServer backup..."
        public static let runtimeDataRestoreCompleted = "VitalServer restore completed."
        public static let folderMissingTitle = "Folder does not exist"
        public static func folderMissingCreateQuestion(path: String) -> String {
            "The folder does not exist:\n\n\(path)\n\nCreate it now?"
        }
        public static func folderCreateFailed(_ message: String) -> String {
            "Could not create folder: \(message)"
        }
        public static let invalidRuntimeURL = "Could not open URL because it is invalid."
        public static func folderReadFailed(_ message: String) -> String {
            "Could not read folders: \(message)"
        }
        public static func dataDirectoryStatsFailed(_ message: String) -> String {
            "Could not read data directory: \(message)"
        }
        public static let missingBackup = "Choose a backup first."
        public static func backupListLoadFailed(_ message: String) -> String {
            "Failed to load backups: \(message)"
        }
        public static func releaseMetadataLoadFailed(_ message: String) -> String {
            "Failed to load release metadata: \(message)"
        }
        public static let invalidBackup = "Selected backup is outside the managed backup directory."
        public static let missingLauncher = "Missing runtime launcher"
        public static let missingBundle = "Choose an update bundle first."
        public static let commandCancelled = "Command was cancelled or failed."
        public static let latestBackupFallback = "Latest backup"
        public static let repairProxyConfirmation = "Stops nginx listeners on the configured proxy port, then restarts the host proxy service. Other process types are reported but not stopped automatically."
        public static let repairDatastoreConfirmation = "Checks and repairs the Redis append-only file inside the VM, then restarts VitalServer containers and host services. Use this only when diagnostics or support identifies Redis datastore corruption. Redis creates a timestamped backup before fixing a damaged AOF file. Repair can truncate the corrupted tail of the AOF; use Redis backups for full data recovery."
        public static let repairVMDiskConfirmation = "Creates a Redis backup first, then archives the current VM disk, recreates it from the installed base image, and restarts runtime services. If the current VM cannot create a Redis backup, repair continues because the old VM disk is archived before replacement. Vital files stored in the configured host directory are preserved."
        public static let repairRuntimeServicesConfirmation = "Restarts the VM runtime services, guest log sync, host proxy, and watchdog. VitalServer may be briefly unavailable while runtime repair runs."
        public static let standardUninstallConfirmation = "Creates a Redis backup first, then removes the Helper app, runtime services, tools, VM disk, and package receipt. Logs, backups, Redis backups, and Vital files are preserved. If Redis backup creation fails, uninstall is stopped."
        public static let cleanUninstallConfirmation = "Removes the Helper app, runtime services, tools, VM disk, logs, backups, Redis backups, package receipt, and configured Vital files directory."
        public static let deleteBackupConfirmation = "Delete the selected update backup? This cannot be undone. VitalServer backups are not deleted."
        public static let deleteRuntimeDataBackupConfirmation = "Delete the selected VitalServer backup? This cannot be undone. Update rollback backups and current runtime data are not deleted."
        public static let restoreRuntimeDataBackupConfirmation = "Restore the selected VitalServer backup? This replaces current runtime data, settings, observability history, and Redis data, and may restart runtime services."
        public static let restoreRedisBackupConfirmation = "Restore the selected Redis-only backup? This replaces current Redis data and may restart runtime services."
        public static let bridgedModeUnavailable = "Bridged mode is not available in this build."
        public static let diskDecreaseUnavailable = "Disk size can only be increased."
        public static let vitalFilesDirectoryRequired = "Vital files directory must be an absolute path."
        public static let vitalFilesDirectoryProtected = "Vital files directory cannot be Desktop, Documents, Downloads, or iCloud Drive. Choose a non-protected local folder such as /Users/Shared/VitalServerHelper/vital-files."
        public static let invalidPort = "Port must be between 1 and 65535."
        public static let invalidAdvertisedURL = "Advertised URLs must be absolute http/https URLs."
        public static let invalidRedisBackupRetention = "VitalServer Helper backups must be between 1 and 30 archives."
        public static let invalidBackupScheduleTimes = "Backup times must use 24-hour HH:mm format, such as 03:15 or 15:15, and must be between 00:00 and 23:59."
        public static let duplicateBackupScheduleTimes = "Backup times must be unique."
        public static let invalidLogArchiveRetention = "Log archive retention must be between 1 and 30 days."
        public static let invalidLogArchiveMaximum = "Log archive size limit must be between 1 and 20 GiB."
        public static let adminPasswordRequired = "Admin password reset value must not be empty."
        public static let adminPasswordNewline = "Admin password reset value must not contain newlines."
        public static let invalidRedisRelayTarget = "Redis relay target settings are invalid."
        public static func commandFailed(exitCode: Int32) -> String {
            "Command failed with exit code \(exitCode)"
        }

        public static func installState(installed isInstalled: Bool) -> String {
            isInstalled ? installed : notInstalled
        }

        public static func installState(_ state: RuntimeFileState) -> String {
            switch state {
            case .executable:
                installed
            case .missing:
                notInstalled
            case .present:
                "Present but not executable"
            case .inspectFailed(let reason):
                reason.isEmpty
                    ? "Installation inspection failed"
                    : "Installation inspection failed: \(reason)"
            case .unknown(let value):
                "Installation state unknown: \(value)"
            }
        }

        public static func launchdState(loaded: Bool) -> String {
            loaded ? running : stopped
        }

        public static func launchdState(_ state: RuntimeServiceState?) -> String {
            guard let state else {
                return unknown
            }
            switch state {
            case .loaded:
                return running
            case .notLoaded:
                return stopped
            case .readFailed:
                return "Read failed"
            case .permissionDenied:
                return "Permission denied"
            case .unknown(let value):
                return titleCasedStatus(value)
            }
        }

        public static func vmState(_ value: RuntimeVMState?) -> String {
            guard let value else {
                return unknown
            }
            switch value {
            case .notInstalled:
                return notInstalled
            case .stopped:
                return stopped
            case .starting:
                return starting
            case .running:
                return running
            case .stale:
                return stale
            case .unreachable:
                return unreachable
            case .failed:
                return failed
            case .unknown(let rawValue):
                return titleCasedStatus(rawValue)
            }
        }

        public static func recorderIngressStatusReadState(
            _ value: RuntimeRecorderIngressStatusReadState?
        ) -> String {
            guard let value else {
                return notReported
            }
            switch value {
            case .loaded:
                return ready
            case .notRead,
                 .commandFailed,
                 .emptyResponse,
                 .outputInvalid,
                 .invalidResponse,
                 .readFailed:
                return notReady
            }
        }

        public static func vmError(_ value: RuntimeVMError) -> String {
            switch value {
            case .missingExecutable:
                return "Missing VM executable"
            case .missingRootfsBase:
                return "Missing rootfs base"
            case .missingDisk:
                return "Missing VM disk"
            case .serviceNotLoaded(let state):
                return "VM service \(titleCasedStatus(state))"
            case .missingIPAddress:
                return "Missing VM IP"
            case .launchFailed(let reason):
                return "VM launch failed (\(titleCasedStatus(reason)))"
            case .invalidConfiguration(let subject):
                return "Invalid VM configuration (\(titleCasedStatus(subject)))"
            case .hostResourceUnavailable(let subject):
                return "Host resource unavailable (\(titleCasedStatus(subject)))"
            case .diskAttachmentInvalid:
                return "VM disk attachment invalid"
            case .guestFilesystemError:
                return "Guest filesystem error"
            case .guestFilesystemReadOnly:
                return "Guest filesystem read-only"
            case .guestDiskIO:
                return "Guest disk I/O error"
            case .guestHTTP(let status):
                return "Guest HTTP \(status)"
            case .guestHTTPProbeFailed(let status):
                return "Guest HTTP probe failed (\(status))"
            case .guestBootstrapMissingRuntimePackages:
                return "Guest bootstrap missing runtime packages"
            case .guestBootstrapDockerRuntimeFailed:
                return "Guest bootstrap Docker runtime failed"
            case .guestBootstrapFailed:
                return "Guest bootstrap failed"
            case .unknown(let rawValue):
                return titleCasedStatus(rawValue)
            }
        }

        public static func failureReason(_ value: RuntimeFailureReason) -> String {
            switch value {
            case .missingVMBin:
                return "Missing VM executable"
            case .missingProxyRunner:
                return "Missing host proxy runner"
            case .missingRootfsBase:
                return "Missing rootfs base"
            case .missingVMDisk:
                return "Missing VM disk"
            case .vmService(let state):
                return "VM service \(titleCasedStatus(state))"
            case .guestLogSyncService(let state):
                return "Guest log sync service \(titleCasedStatus(state))"
            case .proxyService(let state):
                return "Host proxy service \(titleCasedStatus(state))"
            case .watchdogService(let state):
                return "Watchdog service \(titleCasedStatus(state))"
            case .hostProxyHTTP(let status):
                return "Host proxy HTTP \(status)"
            case .redisUIHTTP(let status):
                return "Redis UI HTTP \(status)"
            case .swaggerUIHTTP(let status):
                return "Swagger UI HTTP \(status)"
            case .guestHTTP(let status):
                return "Guest HTTP \(status)"
            case .guestHTTPProbeFailed(let status):
                return "Guest HTTP probe failed (\(status))"
            case .recorderIngressHTTP(let status):
                return "Recorder ingress HTTP \(status)"
            case .containerService(let service, let state):
                return "Container \(service) \(titleCasedStatus(state))"
            case .guestService(let service, let state):
                return "Guest service \(service) \(titleCasedStatus(state))"
            case .guestServiceObservationMissing:
                return "Guest service observation missing"
            case .guestServiceObservationReadFailed(let message):
                return "Guest service observation read failed (\(titleCasedStatus(message)))"
            case .vitalDBAnomaly(let kind, let subject):
                return "VitalDB anomaly \(titleCasedStatus(kind)) on \(subject)"
            case .proxyPortInUse(let port, let listeners):
                return "Host proxy port \(port) in use by \(listeners)"
            case .guestBootstrapMissingRuntimePackages:
                return "Guest bootstrap missing runtime packages"
            case .guestBootstrapDockerRuntimeFailed:
                return "Guest bootstrap Docker runtime failed"
            case .guestBootstrapFailed:
                return "Guest bootstrap failed"
            case .observabilityEventStoreUnavailable:
                return "Observability store unavailable"
            case .observabilityEventStoreCorrupt:
                return "Observability store corrupt"
            case .vmLifecycleDocumentInvalid:
                return "VM lifecycle document invalid"
            case .vmLifecycleDocumentStale:
                return "VM lifecycle document stale"
            case .vmPidFileStale:
                return "VM PID file stale"
            case .vmProcessExited:
                return "VM process exited"
            case .vmDiskAttachmentInvalid:
                return "VM disk attachment invalid"
            case .guestFilesystemError:
                return "Guest filesystem error"
            case .guestFilesystemReadOnly:
                return "Guest filesystem read-only"
            case .guestDiskIO:
                return "Guest disk I/O error"
            case .vmLaunchFailed(let reason):
                return "VM launch failed (\(titleCasedStatus(reason)))"
            case .vmConfigurationInvalid(let subject):
                return "VM configuration invalid (\(titleCasedStatus(subject)))"
            case .hostResourceUnavailable(let subject):
                return "Host resource unavailable (\(titleCasedStatus(subject)))"
            case .launchdServiceCrashed(let service, let exitCode):
                return "\(titleCasedStatus(service)) service crashed with exit \(exitCode)"
            case .launchdServiceThrottled(let service):
                return "\(titleCasedStatus(service)) service throttled"
            case .hostProxyListenerMismatch(let port, let listeners):
                return "Host proxy port \(port) listener mismatch: \(listeners)"
            case .hostProxyListenerScanUnavailable:
                return "Host proxy listener scan unavailable"
            case .hostProxyListenerScanInspectionFailed(let reason):
                return "Host proxy listener scan inspection failed: \(reason)"
            case .hostProxyListenerScanFailed(let port, let exitCode):
                return "Host proxy port \(port) listener scan failed with exit \(exitCode)"
            case .hostProxyConfigInvalid:
                return "Host proxy configuration invalid"
            case .httpProbeTimedOut(let target):
                return "\(titleCasedStatus(target)) HTTP probe timed out"
            case .httpProbeConnectionRefused(let target):
                return "\(titleCasedStatus(target)) HTTP probe connection refused"
            case .containerExited(let service, let exitCode):
                return "Container \(service) exited with \(exitCode)"
            case .containerRestartLoop(let service):
                return "Container \(service) restart loop"
            case .unknown(let rawValue):
                return titleCasedStatus(rawValue)
            }
        }

        public static func domainRecoveryAction(_ value: RuntimeDomainRecoveryAction) -> String {
            switch value {
            case .installRuntime:
                return "Install runtime"
            case .restartVMService:
                return "Restart VM service"
            case .restartProxyService:
                return "Restart host proxy service"
            case .restartWatchdogService:
                return "Restart watchdog service"
            case .waitForGuest:
                return "Wait for guest readiness"
            case .restartGuestAgent:
                return "Restart guest agent"
            case .repairGuestBootstrap:
                return "Repair guest bootstrap"
            case .reconcileGuestStack:
                return "Reconcile Guest stack"
            case .repairProxyConfiguration:
                return "Repair proxy configuration"
            case .freeProxyPort:
                return "Free host proxy port"
            case .inspectVitalDBObservation:
                return "Inspect VitalDB observation"
            case .backupAndRecreateVM:
                return "Back up data and recreate VM"
            case .fixConfiguration:
                return "Fix configuration"
            case .freeHostResources:
                return "Free host resources"
            case .inspectLogs:
                return "Inspect logs"
            }
        }

        public static func domainError(_ value: RuntimeFailureReason) -> String {
            "\(failureReason(value)) (\(domainRecoveryAction(value.recoveryAction)))"
        }

        public static func reachability(httpStatus: String?) -> String {
            guard let httpStatus, !httpStatus.isEmpty else {
                return waiting
            }
            if successfulHTTPStatus(httpStatus) {
                return reachable
            }
            if httpStatus == "failed" {
                return unreachable
            }
            return waiting
        }

        public static func runtimeLifecycle(_ rawValue: String?) -> String {
            guard let rawValue, !rawValue.isEmpty else {
                return unknown
            }
            switch rawValue.lowercased() {
            case "installing":
                return installing
            case "initializing":
                return initializing
            case "updating":
                return updating
            case "recovering":
                return recovering
            case "healthy":
                return healthy
            case "degraded":
                return degraded
            case "critical":
                return critical
            default:
                return titleCasedStatus(rawValue)
            }
        }

        public static func operation(_ rawValue: String?) -> String {
            guard let rawValue, !rawValue.isEmpty else {
                return unknown
            }
            switch rawValue {
            case "install":
                return "Install"
            case "status":
                return "Status"
            case "health":
                return "Health Check"
            case "watchdog":
                return "Watchdog"
            case "configure":
                return "Configure"
            case "verify-bundle":
                return "Verify Bundle"
            case "stage-bundle":
                return "Stage Bundle"
            case "apply-bundle":
                return "Apply Bundle"
            case "activate-guest-update", "activate-update":
                return "Activate Guest Update"
            case "rollback":
                return "Rollback"
            case "redis-backup":
                return "Redis-only Backup"
            case "redis-restore":
                return "Redis-only Restore"
            case "runtime-data-backup":
                return "VitalServer Backup"
            case "runtime-data-restore":
                return "VitalServer Restore"
            case "repair-datastore":
                return "Repair Redis Datastore"
            case "repair-vm-disk":
                return "Repair VM Disk"
            case "repair-proxy":
                return "Repair Proxy"
            case "repair-services":
                return "Repair Runtime"
            case "start-services":
                return "Start Runtime Services"
            case "stop-services":
                return "Stop Runtime Services"
            case "uninstall":
                return "Uninstall"
            default:
                return titleCasedStatus(rawValue)
            }
        }

        public static func progressStepStatus(_ rawValue: String) -> String {
            switch rawValue.lowercased() {
            case "pending":
                return waiting
            case "started":
                return running
            case "completed":
                return done
            case "failed":
                return failed
            case "skipped":
                return skipped
            default:
                return titleCasedStatus(rawValue)
            }
        }

        public static func containerHealth(_ rawValue: String?) -> String {
            guard let rawValue, !rawValue.isEmpty else {
                return waiting
            }
            switch rawValue.lowercased() {
            case "healthy":
                return healthy
            case "unhealthy":
                return unhealthy
            case "starting":
                return starting
            default:
                return titleCasedStatus(rawValue)
            }
        }

        public static func containerState(_ rawValue: String?) -> String {
            guard let rawValue, !rawValue.isEmpty else {
                return waiting
            }
            switch rawValue.lowercased() {
            case "running":
                return running
            case "exited", "dead", "paused", "stopped":
                return stopped
            default:
                return titleCasedStatus(rawValue)
            }
        }

        private static func successfulHTTPStatus(_ value: String) -> Bool {
            guard let code = Int(value) else {
                return false
            }
            return code >= 200 && code < 300
        }

        private static func titleCasedStatus(_ value: String) -> String {
            value
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }

}
