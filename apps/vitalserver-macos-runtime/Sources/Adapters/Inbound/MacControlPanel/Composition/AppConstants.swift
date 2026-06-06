import Foundation
import Contracts
import Errors

public enum AppConstants {
    public enum Product {
        public static let displayName = "VitalServer Helper"
        public static let vitalDBName = "VitalDB"
        public static let vitalDBURL = "https://vitaldb.net"
        public static let poweredByPrefix = "Powered by"
        public static let tiroshName = "Tirosh"
        public static let tiroshURL = "https://www.tirosh.ai/"
        public static let packageIdentifier = "ai.tirosh.vitalserver.helper"
        public static let vitalServerVersion = GeneratedRelease.vitalServerVersion
        public static let defaultProxyPort = 80
        public static func vitalServerURL(proxyPort: Int) -> String {
            "http://127.0.0.1:\(proxyPort)/"
        }
        public static func remoteConsoleURL(port: Int) -> String {
            "http://127.0.0.1:\(port)/"
        }
        public static func runtimeControlDevConsoleURL(port: Int) -> String {
            "http://127.0.0.1:\(port)/dev/runtime-control"
        }
        public static func runtimeControlPWAURL(port: Int) -> String {
            "http://127.0.0.1:\(port)/"
        }
        public static func redisUIURL(proxyPort: Int) -> String {
            "http://127.0.0.1:\(proxyPort)/redis-ui/"
        }
        public static func swaggerURL(proxyPort: Int) -> String {
            "http://127.0.0.1:\(proxyPort)/swagger/"
        }
        public static func hostProxyLivenessURL(proxyPort: Int) -> String {
            "http://127.0.0.1:\(proxyPort)/health"
        }
        public static func hostProxyHealthURL(proxyPort: Int) -> String {
            "http://127.0.0.1:\(proxyPort)/ready"
        }
        public static func guestHealthURL(vmIP: String) -> String {
            "http://\(vmIP)/ready"
        }
    }

    public enum Labels {
        public static let sectionStatus = "Status"
        public static let sectionRecorders = "Recorders"
        public static let sectionBeds = "Beds"
        public static let sectionSettings = "Settings"
        public static let sectionUpdate = "Update"
        public static let sectionObservability = "Observability"
        public static let sectionTest = "Test"
        public static let sectionAdvanced = "Advanced"
        public static let sectionInfo = "About"
        public static let sectionDangerZone = "Danger Zone"
        public static let sectionLog = "Logs"
        public static let sectionMore = "More"
        public static let runtime = "Runtime"
        public static let runtimeDetails = "Runtime details"
        public static let runtimeState = "Runtime state"
        public static let statusDocument = "Status document"
        public static let guestRuntimeState = "Guest runtime state"
        public static let vitalServerURL = "VitalServer URL"
        public static let runtimeControlPWA = "Remote Console"
        public static let dataDirectory = "Data directory"
        public static let actionNeeded = "Action needed"
        public static let recommendedAction = "Recommended action"
        public static let overallHealth = "Overall health"
        public static let resourceUsage = "Resource usage"
        public static let cpuUsage = "CPU"
        public static let memoryUsage = "Memory available to VM"
        public static let resourceUsageHelp = "Memory usage is reported by the Linux guest. It can be slightly lower than the configured allocation because the guest OS reserves memory for kernel and device overhead."
        public static let systemDiskUsage = "VM disk"
        public static let dataStorageUsage = "Data storage"
        public static let healthDetails = "Health details"
        public static let runtimeInstallation = "Runtime installation"
        public static let vmState = "VM state"
        public static let vmIPAddress = "VM IP"
        public static let vmErrors = "VM errors"
        public static let watchdog = "Watchdog"
        public static let vitalDBObserver = "VitalDB Observer"
        public static let vitalRecorder = "Vital Recorder"
        public static let recorderHistory = "Recorder History"
        public static let recorderDetails = "Recorder Details"
        public static let bedDetails = "Bed Details"
        public static let runtimeEvents = "Runtime Events"
        public static let runtimeEventPeriod = "Period"
        public static let runtimeEventFilter = "Filter"
        public static let runtimeEventLimit = "Limit"
        public static let activeRecorderConnections = "Active recorder connections"
        public static let knownRecorders = "Known recorders"
        public static let onlineRecorders = "Online recorders"
        public static let staleRecorders = "Stale recorders"
        public static let knownBeds = "Known beds"
        public static let onlineBeds = "Online beds"
        public static let staleBeds = "Stale beds"
        public static let bedAnomalies = "Bed anomalies"
        public static let recorderAnomalies = "Recorder anomalies"
        public static let latestRecorder = "Latest recorder"
        public static let recorderObservation = "Observation updated"
        public static let recorderSource = "Recorder source"
        public static let recorderSearch = "Search VRecorder"
        public static let bedSearch = "Search Bed"
        public static let recorderStatus = "Status"
        public static let recorderVersion = "Version"
        public static let recorderLastSeen = "Last seen"
        public static let bed = "Bed"
        public static let patient = "Patient"
        public static let anomaly = "Anomaly"
        public static let observations = "Observations"
        public static let operation = "Operation"
        public static let runtimeVersion = "Runtime version"
        public static let updatedAt = "Updated at"
        public static let vmService = "VM service"
        public static let proxyService = "Proxy service"
        public static let guestLogSyncService = "Guest log sync service"
        public static let sleepPreventionService = "Sleep prevention service"
        public static let watchdogService = "Watchdog service"
        public static let proxyPort = "Host proxy port"
        public static let proxyPortHelp = "Port opened on this Mac. Browsers and VRecorder devices connect to this port first, then the Helper forwards traffic into the VM."
        public static let runtimeControlPort = "Remote Console port"
        public static let runtimeControlPortHelp = "Port opened on this Mac for the Remote Console and Runtime Control API. Remote browsers can connect to this port when the Mac is reachable on the network."
        public static let vmIP = "VM IP"
        public static let guestHTTP = "Guest HTTP"
        public static let hostProxy = "Host proxy"
        public static let redisUIHTTP = "Redis UI HTTP"
        public static let swaggerUIHTTP = "Swagger UI HTTP"
        public static let failureReasons = "Failure reasons"
        public static let log = "Log"
        public static let logLines = "Lines"
        public static let logSource = "Source"
        public static let logStreaming = "Live"
        public static let logLive = "Live"
        public static let logPaused = "Paused"
        public static let advancedSummary = "Advanced runtime details"
        public static let advancedDescription = "Diagnostics, service internals, repair actions, update rollback, and administrator operations."
        public static let infoSummary = "Runtime information"
        public static let infoDescription = "Installed versions, bundled services, and deployment details for support and maintenance."
        public static let dangerZoneSummary = "Danger Zone"
        public static let dangerZoneDescription = "Operations here delete recovery assets or remove runtime components. Use them only when you understand the impact."
        public static let sectionProductInfo = "Product"
        public static let sectionBundledServices = "Bundled services"
        public static let sectionRuntimePaths = "Runtime paths"
        public static let sectionRuntimeReplacement = "VM/rootfs updates"
        public static let sectionDestructiveOperations = "Destructive operations"
        public static let sectionDiagnostics = "Diagnostics"
        public static let sectionServiceHealth = "Service health"
        public static let sectionNetworkOverrides = "Advanced network"
        public static let sectionAdminOperations = "Admin operations"
        public static let sectionRecoveryOperations = "Recovery operations"
        public static let sectionRuntimeRepair = "Runtime repair"
        public static let sectionUpdateRecovery = "Update recovery"
        public static let sectionRedisDataRecovery = "Redis data recovery"
        public static let statusReadIssues = "Status read issues"
        public static let adminOperationsHelp = "Use these actions only when administering the installed runtime. Password changes are applied with the same runtime configuration flow as Settings."
        public static let runtimeServiceControlHelp = "Starts or stops the VM, host proxy, and watchdog together. Use Stop for planned maintenance, then Start to bring VitalServer back online."
        public static let recoveryOperationsHelp = "Use these actions when the runtime is installed but unhealthy after update, rollback, or unexpected shutdown."
        public static let updateRecoveryHelp = "Use rollback only when an update leaves the runtime unhealthy. Rollback restores the latest managed backup and restarts runtime services."
        public static let redisDataRecoveryHelp = "Restore Redis data from a verified Redis backup archive. This is separate from update rollback and replaces the current Redis data."
        public static let sectionUpdateSource = "Update source"
        public static let sectionBundleVerification = "Bundle verification"
        public static let sectionApplyUpdate = "Apply update"
        public static let updateProgressLog = "Update progress"
        public static let offlineBundle = "Offline bundle"
        public static let onlineUpdate = "Check for Updates"
        public static let onlineUpdateUnavailable = "Online update is planned for connected sites. Use an offline bundle for this build."
        public static let selectedBundle = "Selected bundle"
        public static let updateSourceHelp = "Air-gapped sites receive an update-bundle .tar.gz file through USB, local file share, or hospital-managed storage."
        public static let bundleVerificationHelp = "Verify checksums before applying. Signature verification is currently reserved by the bundle contract."
        public static let applyUpdateHelp = "Applies the verified bundle and may restart VitalServer services. VM/rootfs level changes are treated as administrator-level updates."
        public static let menuVitalFiles = "Vital Files"
        public static let menuRuntimeServices = "Runtime Services"
        public static let noVitalFileFolders = "No vital file folders"
        public static let sectionVM = "VM"
        public static let sectionNetwork = "Network"
        public static let sectionStorage = "Storage"
        public static let sectionRedisData = "Redis data"
        public static let sectionOperations = "Operations"
        public static let settingsReadIssues = "Settings read issues"
        public static let sectionAdvancedConfiguration = "Advanced configuration"
        public static let cpu = "CPU"
        public static let memory = "Memory allocation"
        public static let memoryAllocationHelp = "Amount of memory assigned to the VM. The maximum is based on this Mac's memory while leaving memory for macOS. The Linux guest may report a slightly lower usable total in Status."
        public static let disk = "Disk"
        public static let mode = "Mode"
        public static let shared = "Shared"
        public static let bridged = "Bridged"
        public static let bridgedUnavailable = "Bridged (not available)"
        public static let bridgedInterface = "Bridged interface"
        public static let sharedNetworkHelp = "Shared/NAT mode is supported in this build. VitalServer is exposed through the Mac host proxy."
        public static let bridgedNetworkHelp = "Bridged mode is planned, but it requires Apple's restricted networking entitlement and is disabled for now."
        public static let sectionAdvertisedURL = "Advertised URL"
        public static let sectionAdvertisedURLOverride = "Advertised service URLs"
        public static let sectionPlannedNetworkFeatures = "Planned network features"
        public static let remoteConsoleURL = "Remote Console URL"
        public static let remoteConsoleURLHelp = "Remote browsers open this URL for the Remote Console and Runtime Control API."
        public static let vitalServerAdvertisedURL = "VitalServer URL"
        public static let vitalServerURLHelp = "URL that VitalServer should advertise to clients, such as https://vitaldb.tirosh.ai/."
        public static let remoteConsoleAdvertisedURL = "Remote Console URL"
        public static let remoteConsoleAdvertisedURLHelp = "URL for Remote Console, such as https://console.tirosh.ai/."
        public static let redisBackupRetention = "Redis backups"
        public static let redisBackupRetentionHelp = "Number of Redis backup archives to keep in Vital files backups, up to 30. Older archives are pruned after a new verified backup is created."
        public static let advertisedURLSameHost = "(same host)"
        public static let advancedNetworkHelp = "These settings change how clients discover VitalServer and Remote Console beyond this Mac's direct host proxy URLs."
        public static let mdnsName = "mDNS / Bonjour name"
        public static let mdnsHelp = "Planned. Would publish a stable .local name such as vitalserver.local from the Mac host."
        public static let bridgedNetworking = "Bridged VM networking"
        public static let bridgedAdvancedHelp = "Planned. Requires Apple restricted networking entitlement and site network approval."
        public static let httpsTermination = "HTTPS / TLS termination"
        public static let httpsTerminationHelp = "Planned. Would terminate HTTPS at the Mac proxy using a hospital CA or managed certificate."
        public static let staticVMAddress = "Static VM address"
        public static let staticVMAddressHelp = "Not available in shared/NAT mode. For bridged deployments, prefer DHCP reservation by fixed VM MAC address."
        public static let vitalFilesDirectory = "Vital files directory"
        public static func diskIncreaseOnlyHelp(_ minimumGiB: Int) -> String {
            "Disk size can only be increased after installation. Current minimum is \(minimumGiB) GiB."
        }
        public static let startOnBoot = "Start on boot"
        public static let automaticRecovery = "Enable automatic recovery"
        public static let automaticRecoveryHelp = "Automatically restarts the VM or network proxy when VitalServer is not ready. Disable only for troubleshooting."
        public static let preventSystemSleep = "Keep Mac awake for VRecorder traffic"
        public static let preventSystemSleepHelp = "Prevents idle system sleep while VitalServer services run so the host proxy, VM, and VRecorder TCP streams stay online. The screen can still lock. Manual Sleep, lid close, shutdown, or managed power policy can still disconnect the network."
        public static let restartServicesAfterSave = "Restart services after save"
        public static let resetAdminPassword = "Reset admin password"
        public static let newAdminPassword = "New admin password"
        public static let rollbackBackup = "Rollback backup"
        public static let selectedBackup = "Selected backup"
        public static let backupSize = "Backup size"
        public static let latestBackup = "Latest backup"
        public static let helperVersion = "VitalServer Helper version"
        public static let installedRuntimeVersion = "Installed runtime version"
        public static let vitalServerVersion = "VitalServer version"
        public static let appBundle = "App bundle"
        public static let runtimeHome = "Runtime home"
        public static let packageIdentifier = "Package identifier"
        public static let backupDirectory = "Backup directory"
        public static let serviceName = "Service"
        public static let serviceImage = "Image"
        public static let serviceVersion = "Version"
        public static let serviceBundled = "Bundled"
        public static let enabled = "Enabled"
        public static let status = "Status"
        public static let url = "URL"
        public static let session = "Session"
        public static let sessions = "Sessions"
        public static let messages = "Messages"
        public static let bytes = "Bytes"
        public static let lastError = "Last error"
        public static let target = "Target"
        public static let scenario = "Scenario"
        public static let signal = "Signal"
        public static let bedSetup = "Bed setup"
        public static let bedSelection = "Bed selection"
        public static let beds = "Beds"
        public static let bedCount = "Beds"
        public static let bedPrefix = "Bed prefix"
        public static let selectedBeds = "Selected beds"
        public static let virtualVRecorderSession = "Virtual VRecorder session"
        public static let trafficProfile = "Traffic profile"
        public static let recorders = "Recorders"
        public static let recorderCount = "VRecorders"
        public static let interval = "Interval"
        public static let duration = "Duration"
        public static let maxMessages = "Max messages"
        public static let shiftTime = "Shift time"
        public static let generateFrames = "Generate frames"
        public static let vrcodeOptional = "VRecorder code (optional)"
        public static let orphanVrcode = "Orphan VRecorder code"
        public static let vmRootfsUpdatePlanned = "VM/rootfs bundle update is planned for this area. Use offline bundle updates for regular application/runtime updates."
        public static let destructiveOperationsHelp = "Uninstall removes installed services and runtime files. Choose clean uninstall only when preserved data can also be removed."
        public static let appBundlePath = "App bundle path"
        public static let noUpdateBundleSelected = "No update bundle selected"
        public static let unitVCPU = "vCPU"
        public static let unitGiB = "GiB"
        public static func openServiceHelp(_ serviceName: String) -> String {
            "Open \(serviceName)"
        }
    }

    public enum StatusText {
        public static let ready = "Ready"
        public static let vitalServerUnavailable = "VitalServer is unavailable"
        public static let vitalServerNeedsAttention = "VitalServer needs attention"
        public static let runtimeNotInstalled = "Runtime is not installed"
        public static let noRuntimeEvents = "No runtime events"
        public static let allRuntimeEvents = "All events"
        public static let noVitalRecorderObservations = "No Vital Recorder observations"
        public static let noBedObservations = "No bed observations"
        public static let selectBed = "Select a bed to view details."
        public static let noRecorderAnomalies = "No recorder anomalies"
        public static let unavailable = "Unavailable"
        public static let healthy = "Healthy"
        public static let unhealthy = "Unhealthy"
        public static let starting = "Starting"
        public static let installing = "Installing"
        public static let updating = "Updating"
        public static let recovering = "Recovering"
        public static let degraded = "Degraded"
        public static let needsAttention = "Needs attention"
        public static let critical = "Critical"
        public static let running = "Running"
        public static let stopped = "Stopped"
        public static let reachable = "Reachable"
        public static let unreachable = "Unreachable"
        public static let installed = "Installed"
        public static let notInstalled = "Not Installed"
        public static let waiting = "Waiting"
        public static let notChecked = "Not checked"
        public static let planned = "Planned"
        public static let notAvailable = "Not Available"
        public static let noLogData = "No log data for this source yet."
        public static let unknown = "Unknown"
        public static let notReported = "Not reported"
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
        public static let runtimeServicesStartPreparing = "Preparing runtime service start..."
        public static let runtimeServicesStartRunning = "Starting runtime services..."
        public static let runtimeServicesStarted = "Runtime services started."
        public static let runtimeServicesStopPreparing = "Preparing runtime service stop..."
        public static let runtimeServicesStopRunning = "Stopping runtime services..."
        public static let runtimeServicesStopped = "Runtime services stopped."
        public static let settingsApplyPreparing = "Preparing runtime settings..."
        public static let settingsApplyRunning = "Applying runtime settings..."
        public static let settingsApplied = "Runtime settings applied."
        public static let applySettingsConfirmation = "Apply these settings to the installed runtime?\n\nThis may update launchd services, rewrite runtime configuration, and restart the VM/proxy services when restart is enabled."
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
        public static let backupDeleted = "Backup deleted."
        public static let backupDeletePreparing = "Preparing backup deletion..."
        public static let backupDeleteRunning = "Deleting backup..."
        public static let redisBackupPreparing = "Preparing Redis backup..."
        public static let redisBackupRunning = "Creating Redis backup..."
        public static let redisBackupCompleted = "Redis backup completed."
        public static let folderMissingTitle = "Folder does not exist"
        public static func folderMissingCreateQuestion(path: String) -> String {
            "The folder does not exist:\n\n\(path)\n\nCreate it now?"
        }
        public static func folderCreateFailed(_ message: String) -> String {
            "Could not create folder: \(message)"
        }
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
        public static let invalidBackup = "Selected backup is outside the managed backup directory."
        public static let missingLauncher = "Missing runtime launcher"
        public static let missingBundle = "Choose an update bundle first."
        public static let commandCancelled = "Command was cancelled or failed."
        public static let latestBackupFallback = "Latest backup"
        public static let repairProxyConfirmation = "Stops nginx listeners on the configured proxy port, then restarts the host proxy service. Other process types are reported but not stopped automatically."
        public static let repairDatastoreConfirmation = "Checks and repairs the Redis append-only file inside the VM, then restarts VitalServer containers and host services. Redis creates a timestamped backup before fixing a damaged AOF file. Repair can truncate the corrupted tail of the AOF; use Redis backups for full data recovery."
        public static let repairVMDiskConfirmation = "Creates a Redis backup first, then archives the current VM disk, recreates it from the installed base image, and restarts runtime services. If the current VM cannot create a Redis backup, repair continues because the old VM disk is archived before replacement. Vital files stored in the configured host directory are preserved."
        public static let repairRuntimeServicesConfirmation = "Restarts the VM, guest log sync, host proxy, and watchdog services. VitalServer may be briefly unavailable while services restart."
        public static let startRuntimeServicesConfirmation = "Starts the VM, host proxy, and watchdog services, then waits for VitalServer to become healthy."
        public static let stopRuntimeServicesConfirmation = "Stops the watchdog, host proxy, and VM services. VitalServer will be unavailable until runtime services are started again."
        public static let standardUninstallConfirmation = "Creates a Redis backup first, then removes the Helper app, runtime services, tools, VM disk, and package receipt. Logs, backups, Redis backups, and Vital files are preserved. If Redis backup creation fails, uninstall is stopped."
        public static let cleanUninstallConfirmation = "Removes the Helper app, runtime services, tools, VM disk, logs, backups, Redis backups, package receipt, and configured Vital files directory."
        public static let deleteBackupConfirmation = "Delete the selected managed backup? This cannot be undone."
        public static let bridgedModeUnavailable = "Bridged mode is not available in this build."
        public static let diskDecreaseUnavailable = "Disk size can only be increased."
        public static let vitalFilesDirectoryRequired = "Vital files directory must be an absolute path."
        public static let vitalFilesDirectoryProtected = "Vital files directory cannot be Desktop, Documents, Downloads, or iCloud Drive. Choose a non-protected local folder such as /Users/Shared/VitalServerHelper/vital-files."
        public static let invalidPort = "Port must be between 1 and 65535."
        public static let invalidAdvertisedURL = "Advertised URLs must be absolute http/https URLs."
        public static let invalidRedisBackupRetention = "Redis backups must be between 1 and 30 archives."
        public static let adminPasswordRequired = "Admin password reset value must not be empty."
        public static let adminPasswordNewline = "Admin password reset value must not contain newlines."
        public static func commandFailed(exitCode: Int32) -> String {
            "Command failed with exit code \(exitCode)"
        }

        public static func installState(installed isInstalled: Bool) -> String {
            isInstalled ? installed : notInstalled
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
            case .runtimeStateMissing:
                return "Guest runtime state missing"
            case .runtimeStateInvalid:
                return "Guest runtime state invalid"
            case .runtimeStateStale:
                return "Guest runtime state stale"
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
            case .guestBootstrapResultMissing:
                return "Guest bootstrap result missing"
            case .guestBootstrapResultUnavailable:
                return "Guest bootstrap result unavailable"
            case .guestBootstrapMissingRuntimePackages:
                return "Guest bootstrap missing runtime packages"
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
            case .guestRuntimeStateStale:
                return "Guest runtime state stale"
            case .auditProxyHTTP(let status):
                return "Audit proxy HTTP \(status)"
            case .containerService(let service, let state):
                return "Container \(service) \(titleCasedStatus(state))"
            case .containerObservationMissing:
                return "Container observation missing"
            case .containerObservationReadFailed(let message):
                return "Container observation read failed (\(titleCasedStatus(message)))"
            case .vitalDBAnomaly(let kind, let subject):
                return "VitalDB anomaly \(titleCasedStatus(kind)) on \(subject)"
            case .vitalDBObservationMissing:
                return "VitalDB observation missing"
            case .vitalDBObservationReadFailed(let message):
                return "VitalDB observation read failed (\(titleCasedStatus(message)))"
            case .proxyPortInUse(let port, let listeners):
                return "Host proxy port \(port) in use by \(listeners)"
            case .guestBootstrapResultMissing:
                return "Guest bootstrap result missing"
            case .guestBootstrapResultUnavailable:
                return "Guest bootstrap result unavailable"
            case .guestBootstrapMissingRuntimePackages:
                return "Guest bootstrap missing runtime packages"
            case .guestBootstrapFailed:
                return "Guest bootstrap failed"
            case .runtimeStatusDocumentMissing:
                return "Runtime status missing"
            case .runtimeStatusDocumentStale:
                return "Runtime status stale"
            case .runtimeStatusDocumentInvalid:
                return "Runtime status invalid"
            case .guestRuntimeStateInvalid:
                return "Guest runtime state invalid"
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
            case .launchdServiceCrashed(let service, let exitCode):
                return "\(titleCasedStatus(service)) service crashed with exit \(exitCode)"
            case .launchdServiceThrottled(let service):
                return "\(titleCasedStatus(service)) service throttled"
            case .hostProxyListenerMismatch(let port, let listeners):
                return "Host proxy port \(port) listener mismatch: \(listeners)"
            case .hostProxyListenerScanUnavailable:
                return "Host proxy listener scan unavailable"
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
            case .vitalDBObservationStale:
                return "VitalDB observation stale"
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
            case .restartContainerServices:
                return "Restart container services"
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
                return "Redis Backup"
            case "repair-datastore":
                return "Repair Data Store"
            case "repair-vm-disk":
                return "Repair VM Disk"
            case "repair-proxy":
                return "Repair Proxy"
            case "repair-services":
                return "Repair Runtime Services"
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
