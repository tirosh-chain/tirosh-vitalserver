import Foundation
import Contracts

enum AppConstants {
    enum Product {
        static let displayName = "VitalServer Helper"
        static let vitalDBName = "VitalDB"
        static let vitalDBURL = "https://vitaldb.net"
        static let poweredByPrefix = "Powered by"
        static let tiroshName = "Tirosh"
        static let tiroshURL = "https://www.tirosh.ai/"
        static let packageIdentifier = "com.tirosh.vitalserver.vm"
        static let vitalServerVersion = GeneratedRelease.vitalServerVersion
        static let defaultProxyPort = 80
        static func vitalServerURL(proxyPort: Int) -> String {
            "http://127.0.0.1:\(proxyPort)/"
        }
        static func redisUIURL(proxyPort: Int) -> String {
            "http://127.0.0.1:\(proxyPort)/redis-ui/"
        }
        static func swaggerURL(proxyPort: Int) -> String {
            "http://127.0.0.1:\(proxyPort)/swagger/"
        }
        static func hostProxyLivenessURL(proxyPort: Int) -> String {
            "http://127.0.0.1:\(proxyPort)/health"
        }
        static func hostProxyHealthURL(proxyPort: Int) -> String {
            "http://127.0.0.1:\(proxyPort)/ready"
        }
        static func guestHealthURL(vmIP: String) -> String {
            "http://\(vmIP)/ready"
        }
    }

    enum SettingsLimits {
        static let minimumCPUCount = 7
        static let maximumCPUCount = 64
        static let minimumSystemCPUCountForDynamicLimit = 8
        static var maximumAllowedCPUCount: Int {
            let systemCPUCount = ProcessInfo.processInfo.processorCount
            guard systemCPUCount >= minimumSystemCPUCountForDynamicLimit else {
                return minimumCPUCount
            }
            return min(maximumCPUCount, systemCPUCount)
        }
        static let defaultDiskGiB = 32
        static let minimumDiskGiB = 4
        static let maximumDiskGiB = 512
        static let diskStepGiB = 4
        static let minimumMemoryGiB = 4
        static let maximumMemoryGiB = 64
        static let reservedHostMemoryGiB = 4
        static let memoryStepGiB = 4
        static var maximumAllowedMemoryGiB: Int {
            let physicalMemoryGiB = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
            let hostAwareMaximum = physicalMemoryGiB - reservedHostMemoryGiB
            let cappedMaximum = min(maximumMemoryGiB, hostAwareMaximum)
            let steppedMaximum = (cappedMaximum / memoryStepGiB) * memoryStepGiB
            return max(minimumMemoryGiB, steppedMaximum)
        }
        static let minimumRedisBackupRetentionCount = 1
        static let maximumRedisBackupRetentionCount = 30
        static let redisBackupRetentionStep = 1
    }

    enum ServiceVersions {
        static let vitalServerImage = GeneratedRelease.vitalServerImage
        static let redisImage = GeneratedRelease.redisImage
        static let redisUIImage = GeneratedRelease.redisUIImage
        static let swaggerUIImage = GeneratedRelease.swaggerUIImage
        static let guestEdgeImage = GeneratedRelease.guestEdgeImage
        static let hostProxy = GeneratedRelease.hostProxyImage
        static let redisVersion = GeneratedRelease.redisVersion
        static let redisUIVersion = GeneratedRelease.redisUIVersion
        static let swaggerUIVersion = GeneratedRelease.swaggerUIVersion
        static let guestEdgeVersion = GeneratedRelease.guestEdgeVersion
        static let hostProxyVersion = GeneratedRelease.hostProxyVersion
    }

    enum Labels {
        static let sectionStatus = "Status"
        static let sectionRecorders = "Recorders"
        static let sectionBeds = "Beds"
        static let sectionSettings = "Settings"
        static let sectionUpdate = "Update"
        static let sectionObservability = "Observability"
        static let sectionTest = "Test"
        static let sectionAdvanced = "Advanced"
        static let sectionInfo = "About"
        static let sectionDangerZone = "Danger Zone"
        static let sectionLog = "Logs"
        static let sectionMore = "More"
        static let runtime = "Runtime"
        static let runtimeDetails = "Runtime details"
        static let runtimeState = "Runtime state"
        static let vitalServerURL = "VitalServer URL"
        static let dataDirectory = "Data directory"
        static let actionNeeded = "Action needed"
        static let recommendedAction = "Recommended action"
        static let overallHealth = "Overall health"
        static let resourceUsage = "Resource usage"
        static let cpuUsage = "CPU"
        static let memoryUsage = "Memory available to VM"
        static let resourceUsageHelp = "Memory usage is reported by the Linux guest. It can be slightly lower than the configured allocation because the guest OS reserves memory for kernel and device overhead."
        static let systemDiskUsage = "VM disk"
        static let dataStorageUsage = "Data storage"
        static let healthDetails = "Health details"
        static let runtimeInstallation = "Runtime installation"
        static let vmState = "VM state"
        static let vmIPAddress = "VM IP"
        static let vmErrors = "VM errors"
        static let watchdog = "Watchdog"
        static let vitalDBObserver = "VitalDB Observer"
        static let vitalRecorder = "Vital Recorder"
        static let recorderHistory = "Recorder History"
        static let recorderDetails = "Recorder Details"
        static let bedDetails = "Bed Details"
        static let runtimeEvents = "Runtime Events"
        static let activeRecorderConnections = "Active recorder connections"
        static let knownRecorders = "Known recorders"
        static let onlineRecorders = "Online recorders"
        static let staleRecorders = "Stale recorders"
        static let knownBeds = "Known beds"
        static let onlineBeds = "Online beds"
        static let staleBeds = "Stale beds"
        static let bedAnomalies = "Bed anomalies"
        static let recorderAnomalies = "Recorder anomalies"
        static let latestRecorder = "Latest recorder"
        static let recorderObservation = "Observation updated"
        static let recorderSource = "Recorder source"
        static let recorderSearch = "Search VRecorder"
        static let bedSearch = "Search Bed"
        static let recorderStatus = "Status"
        static let recorderVersion = "Version"
        static let recorderLastSeen = "Last seen"
        static let bed = "Bed"
        static let patient = "Patient"
        static let anomaly = "Anomaly"
        static let observations = "Observations"
        static let operation = "Operation"
        static let runtimeVersion = "Runtime version"
        static let updatedAt = "Updated at"
        static let vmService = "VM service"
        static let proxyService = "Proxy service"
        static let guestLogSyncService = "Guest log sync service"
        static let sleepPreventionService = "Sleep prevention service"
        static let watchdogService = "Watchdog service"
        static let proxyPort = "Host proxy port"
        static let proxyPortHelp = "Port opened on this Mac. Browsers and VRecorder devices connect to this port first, then the Helper forwards traffic into the VM."
        static let vmIP = "VM IP"
        static let guestHTTP = "Guest HTTP"
        static let hostProxy = "Host proxy"
        static let redisUIHTTP = "Redis UI HTTP"
        static let swaggerUIHTTP = "Swagger UI HTTP"
        static let failureReasons = "Failure reasons"
        static let log = "Log"
        static let logLines = "Lines"
        static let logSource = "Source"
        static let logStreaming = "Live"
        static let logLive = "Live"
        static let logPaused = "Paused"
        static let advancedSummary = "Advanced runtime details"
        static let advancedDescription = "Diagnostics, service internals, repair actions, update rollback, and administrator operations."
        static let infoSummary = "Runtime information"
        static let infoDescription = "Installed versions, bundled services, and deployment details for support and maintenance."
        static let dangerZoneSummary = "Danger Zone"
        static let dangerZoneDescription = "Operations here delete recovery assets or remove runtime components. Use them only when you understand the impact."
        static let sectionProductInfo = "Product"
        static let sectionBundledServices = "Bundled services"
        static let sectionRuntimePaths = "Runtime paths"
        static let sectionRuntimeReplacement = "VM/rootfs updates"
        static let sectionDestructiveOperations = "Destructive operations"
        static let sectionDiagnostics = "Diagnostics"
        static let sectionServiceHealth = "Service health"
        static let sectionNetworkOverrides = "Advanced network"
        static let sectionAdminOperations = "Admin operations"
        static let sectionRecoveryOperations = "Recovery operations"
        static let sectionRuntimeRepair = "Runtime repair"
        static let sectionUpdateRecovery = "Update recovery"
        static let sectionRedisDataRecovery = "Redis data recovery"
        static let adminOperationsHelp = "Use these actions only when administering the installed runtime. Password changes are applied with the same runtime configuration flow as Settings."
        static let runtimeServiceControlHelp = "Starts or stops the VM, host proxy, and watchdog together. Use Stop for planned maintenance, then Start to bring VitalServer back online."
        static let recoveryOperationsHelp = "Use these actions when the runtime is installed but unhealthy after update, rollback, or unexpected shutdown."
        static let updateRecoveryHelp = "Use rollback only when an update leaves the runtime unhealthy. Rollback restores the latest managed backup and restarts runtime services."
        static let redisDataRecoveryHelp = "Restore Redis data from a verified Redis backup archive. This is separate from update rollback and replaces the current Redis data."
        static let sectionUpdateSource = "Update source"
        static let sectionBundleVerification = "Bundle verification"
        static let sectionApplyUpdate = "Apply update"
        static let updateProgressLog = "Update progress"
        static let offlineBundle = "Offline bundle"
        static let onlineUpdate = "Check for Updates"
        static let onlineUpdateUnavailable = "Online update is planned for connected sites. Use an offline bundle for this build."
        static let selectedBundle = "Selected bundle"
        static let updateSourceHelp = "Air-gapped sites receive an update-bundle .tar.gz file through USB, local file share, or hospital-managed storage."
        static let bundleVerificationHelp = "Verify checksums before applying. Signature verification is currently reserved by the bundle contract."
        static let applyUpdateHelp = "Applies the verified bundle and may restart VitalServer services. VM/rootfs level changes are treated as administrator-level updates."
        static let menuVitalFiles = "Vital Files"
        static let menuRuntimeServices = "Runtime Services"
        static let noVitalFileFolders = "No vital file folders"
        static let sectionVM = "VM"
        static let sectionNetwork = "Network"
        static let sectionStorage = "Storage"
        static let sectionRedisData = "Redis data"
        static let sectionOperations = "Operations"
        static let sectionAdvancedConfiguration = "Advanced configuration"
        static let cpu = "CPU"
        static let memory = "Memory allocation"
        static let memoryAllocationHelp = "Amount of memory assigned to the VM. The maximum is based on this Mac's memory while leaving memory for macOS. The Linux guest may report a slightly lower usable total in Status."
        static let disk = "Disk"
        static let mode = "Mode"
        static let shared = "Shared"
        static let bridged = "Bridged"
        static let bridgedUnavailable = "Bridged (not available)"
        static let bridgedInterface = "Bridged interface"
        static let sharedNetworkHelp = "Shared/NAT mode is supported in this build. VitalServer is exposed through the Mac host proxy."
        static let bridgedNetworkHelp = "Bridged mode is planned, but it requires Apple's restricted networking entitlement and is disabled for now."
        static let sectionMacExposure = "Host proxy"
        static let sectionAdvertisedURL = "Advertised URL"
        static let sectionAdvertisedURLOverride = "Advertised URL override"
        static let sectionPlannedNetworkFeatures = "Planned network features"
        static let customAdvertisedURL = "Custom advertised URL"
        static let customAdvertisedURLHelp = "Enable only when clients reach VitalServer through a different external URL than this Mac's host proxy, such as a hospital reverse proxy, NAT port-forward, or HTTPS endpoint."
        static let defaultAdvertisedURL = "Default advertised URL"
        static let defaultAdvertisedURLHelp = "Uses the same host clients connected to and the Host proxy port. This is correct for direct Mac-hosted installs."
        static let publicHost = "Advertised host"
        static let publicHostHelp = "External host name or IP written into VitalServer runtime config."
        static let publicPort = "Advertised port"
        static let publicPortHelp = "External port that VitalServer should advertise to clients."
        static let redisBackupRetention = "Redis backups"
        static let redisBackupRetentionHelp = "Number of Redis backup archives to keep in Vital files backups, up to 30. Older archives are pruned after a new verified backup is created."
        static let advertisedURLPreview = "Advertised URL preview"
        static let advertisedURLSameHost = "(same host)"
        static let advancedNetworkHelp = "These settings change how VitalServer is exposed outside the VM. Most installs only need the Host proxy port."
        static let mdnsName = "mDNS / Bonjour name"
        static let mdnsHelp = "Planned. Would publish a stable .local name such as vitalserver.local from the Mac host."
        static let bridgedNetworking = "Bridged VM networking"
        static let bridgedAdvancedHelp = "Planned. Requires Apple restricted networking entitlement and site network approval."
        static let httpsTermination = "HTTPS / TLS termination"
        static let httpsTerminationHelp = "Planned. Would terminate HTTPS at the Mac proxy using a hospital CA or managed certificate."
        static let staticVMAddress = "Static VM address"
        static let staticVMAddressHelp = "Not available in shared/NAT mode. For bridged deployments, prefer DHCP reservation by fixed VM MAC address."
        static let vitalFilesDirectory = "Vital files directory"
        static func diskIncreaseOnlyHelp(_ minimumGiB: Int) -> String {
            "Disk size can only be increased after installation. Current minimum is \(minimumGiB) GiB."
        }
        static let startOnBoot = "Start on boot"
        static let automaticRecovery = "Enable automatic recovery"
        static let automaticRecoveryHelp = "Automatically restarts the VM or network proxy when VitalServer is not ready. Disable only for troubleshooting."
        static let preventSystemSleep = "Keep Mac awake for VRecorder traffic"
        static let preventSystemSleepHelp = "Prevents idle system sleep while VitalServer services run so the host proxy, VM, and VRecorder TCP streams stay online. The screen can still lock. Manual Sleep, lid close, shutdown, or managed power policy can still disconnect the network."
        static let restartServicesAfterSave = "Restart services after save"
        static let resetAdminPassword = "Reset admin password"
        static let newAdminPassword = "New admin password"
        static let rollbackBackup = "Rollback backup"
        static let selectedBackup = "Selected backup"
        static let backupSize = "Backup size"
        static let latestBackup = "Latest backup"
        static let helperVersion = "VitalServer Helper version"
        static let installedRuntimeVersion = "Installed runtime version"
        static let vitalServerVersion = "VitalServer version"
        static let appBundle = "App bundle"
        static let runtimeHome = "Runtime home"
        static let packageIdentifier = "Package identifier"
        static let backupDirectory = "Backup directory"
        static let serviceName = "Service"
        static let serviceImage = "Image"
        static let serviceVersion = "Version"
        static let serviceBundled = "Bundled"
        static let enabled = "Enabled"
        static let status = "Status"
        static let url = "URL"
        static let session = "Session"
        static let sessions = "Sessions"
        static let messages = "Messages"
        static let bytes = "Bytes"
        static let lastError = "Last error"
        static let target = "Target"
        static let scenario = "Scenario"
        static let signal = "Signal"
        static let recorders = "Recorders"
        static let recorderCount = "VRecorders"
        static let interval = "Interval"
        static let duration = "Duration"
        static let maxMessages = "Max messages"
        static let shiftTime = "Shift time"
        static let generateFrames = "Generate frames"
        static let vrcodeOptional = "VRecorder code (optional)"
        static let orphanVrcode = "Orphan VRecorder code"
        static let vmRootfsUpdatePlanned = "VM/rootfs bundle update is planned for this area. Use offline bundle updates for regular application/runtime updates."
        static let destructiveOperationsHelp = "Uninstall removes installed services and runtime files. Choose clean uninstall only when preserved data can also be removed."
        static let appBundlePath = "App bundle path"
        static let noUpdateBundleSelected = "No update bundle selected"
        static let unitVCPU = "vCPU"
        static let unitGiB = "GiB"
        static func openServiceHelp(_ serviceName: String) -> String {
            "Open \(serviceName)"
        }
    }

    enum Values {
        static let boolTrue = "true"
        static let boolFalse = "false"
        static let empty = "-"
        static let unlimited = "Unlimited"
    }

    enum Actions {
        static let healthCheck = "Health Check"
        static let open = "Open"
        static let openVitalFilesDirectory = "Open Vital Files Directory"
        static let refresh = "Refresh"
        static let repairProxy = "Repair Proxy"
        static let repairProxyPort = "Repair Proxy Port"
        static let repairDatastore = "Repair Data Store"
        static let repairRuntimeServices = "Repair Runtime Services"
        static let uninstall = "Uninstall"
        static let standardUninstall = "Uninstall..."
        static let cleanUninstall = "Clean Uninstall..."
        static let vmRootfsUpdate = "VM/rootfs Update"
        static let applySettings = "Apply"
        static let chooseDirectory = "Choose..."
        static let chooseBundle = "Choose Bundle"
        static let verifyBundle = "Verify"
        static let applyBundle = "Apply Bundle"
        static let rollback = "Rollback"
        static let createRedisBackup = "Create Redis Backup"
        static let restoreRedisBackup = "Restore Redis Backup"
        static let deleteBackup = "Delete Backup"
        static let checkRecorders = "Check Recorders"
        static let openBackups = "Open Backups"
        static let openLogs = "Open Logs"
        static let exportLogs = "Export Logs"
        static let start = "Start"
        static let stop = "Stop"
        static let delete = "Delete"
        static let deleteVRecorder = "Delete VRecorder"
        static let reset = "Reset"
        static let startRuntimeServices = "Start Runtime Services"
        static let stopRuntimeServices = "Stop Runtime Services"
        static let startUpdate = "Start Update"
        static let startRollback = "Start Rollback"
        static let ok = "OK"
        static let cancel = "Cancel"
        static let createFolder = "Create Folder"
        static let continueAction = "Continue"
        static let back = "Back"
        static let install = "Install"
    }

    enum StatusText {
        static let ready = "Ready"
        static let vitalServerUnavailable = "VitalServer is unavailable"
        static let vitalServerNeedsAttention = "VitalServer needs attention"
        static let runtimeNotInstalled = "Runtime is not installed"
        static let noRuntimeEvents = "No runtime events"
        static let noVitalRecorderObservations = "No Vital Recorder observations"
        static let noBedObservations = "No bed observations"
        static let selectBed = "Select a bed to view details."
        static let noRecorderAnomalies = "No recorder anomalies"
        static let unavailable = "Unavailable"
        static let healthy = "Healthy"
        static let unhealthy = "Unhealthy"
        static let starting = "Starting"
        static let installing = "Installing"
        static let updating = "Updating"
        static let recovering = "Recovering"
        static let degraded = "Degraded"
        static let needsAttention = "Needs attention"
        static let critical = "Critical"
        static let running = "Running"
        static let stopped = "Stopped"
        static let reachable = "Reachable"
        static let unreachable = "Unreachable"
        static let installed = "Installed"
        static let notInstalled = "Not Installed"
        static let waiting = "Waiting"
        static let notChecked = "Not checked"
        static let planned = "Planned"
        static let notAvailable = "Not Available"
        static let noLogData = "No log data for this source yet."
        static let unknown = "Unknown"
        static let online = "Online"
        static let offline = "Offline"
        static let stale = "Stale"
        static let failed = "Failed"
        static let skipped = "Skipped"
        static let done = "Done"
        static let actionUnavailable = "This action is not available for the current runtime connection."
        static let healthCheckCompleted = "Health check completed"
        static let missingUninstaller = "Missing uninstaller"
        static let uninstallPreparing = "Preparing runtime removal..."
        static let uninstallWaitingForPrivilege = "Waiting for administrator approval..."
        static let uninstallRunning = "Removing runtime..."
        static let uninstallCompleted = "Runtime removal completed."
        static let cleanUninstallCompleted = "Runtime and preserved data removal completed."
        static let applicationWillQuit = "The Helper app will quit now."
        static let proxyRepairPreparing = "Preparing host proxy repair..."
        static let proxyRepairRunning = "Repairing host proxy..."
        static let proxyRepairCompleted = "Host proxy repair completed."
        static let datastoreRepairPreparing = "Preparing data store repair..."
        static let datastoreRepairRunning = "Repairing data store..."
        static let datastoreRepairCompleted = "Data store repair completed."
        static let runtimeServicesRepairPreparing = "Preparing runtime services repair..."
        static let runtimeServicesRepairRunning = "Restarting runtime services..."
        static let runtimeServicesRepaired = "Runtime services repaired."
        static let logExportPreparing = "Preparing log export..."
        static let logExportCompleted = "Logs exported."
        static let logExportFailed = "Log export failed."
        static let logExportUnavailable = "Log export is not available for this runtime connection."
        static let runtimeServicesStartPreparing = "Preparing runtime service start..."
        static let runtimeServicesStartRunning = "Starting runtime services..."
        static let runtimeServicesStarted = "Runtime services started."
        static let runtimeServicesStopPreparing = "Preparing runtime service stop..."
        static let runtimeServicesStopRunning = "Stopping runtime services..."
        static let runtimeServicesStopped = "Runtime services stopped."
        static let settingsApplyPreparing = "Preparing runtime settings..."
        static let settingsApplyRunning = "Applying runtime settings..."
        static let settingsApplied = "Runtime settings applied."
        static let applySettingsConfirmation = "Apply these settings to the installed runtime?\n\nThis may update launchd services, rewrite runtime configuration, and restart the VM/proxy services when restart is enabled."
        static let updateBundleApplied = "Update bundle applied."
        static let updateBundleAppliedRelaunching = "Update bundle applied. Relaunching VitalServer Helper..."
        static let updateBundlePreparing = "Preparing update bundle..."
        static let updateBundleApplying = "Applying update bundle..."
        static let updateBundleVerifying = "Verifying update bundle..."
        static let updateBundleVerified = "Update bundle verified."
        static let updateBundleVerificationFailed = "Update bundle verification failed."
        static let updateBundleNotVerified = "Verify the update bundle before applying it."
        static let updateBundleConfirmation = "Apply this verified bundle?\n\nThis may restart VitalServer services. Detailed progress is written to the Command log and Update activation log."
        static let rollbackCompleted = "Rollback completed."
        static let rollbackPreparing = "Preparing rollback..."
        static let rollbackRunning = "Rolling back runtime..."
        static let backupDeleted = "Backup deleted."
        static let backupDeletePreparing = "Preparing backup deletion..."
        static let backupDeleteRunning = "Deleting backup..."
        static let redisBackupPreparing = "Preparing Redis backup..."
        static let redisBackupRunning = "Creating Redis backup..."
        static let redisBackupCompleted = "Redis backup completed."
        static let folderMissingTitle = "Folder does not exist"
        static func folderMissingCreateQuestion(path: String) -> String {
            "The folder does not exist:\n\n\(path)\n\nCreate it now?"
        }
        static func folderCreateFailed(_ message: String) -> String {
            "Could not create folder: \(message)"
        }
        static let missingBackup = "Choose a backup first."
        static let invalidBackup = "Selected backup is outside the managed backup directory."
        static let missingLauncher = "Missing runtime launcher"
        static let missingBundle = "Choose an update bundle first."
        static let commandCancelled = "Command was cancelled or failed."
        static let latestBackupFallback = "Latest backup"
        static let repairProxyConfirmation = "Stops nginx listeners on the configured proxy port, then restarts the host proxy service. Other process types are reported but not stopped automatically."
        static let repairDatastoreConfirmation = "Checks and repairs the Redis append-only file inside the VM, then restarts VitalServer containers and host services. Redis creates a timestamped backup before fixing a damaged AOF file. Repair can truncate the corrupted tail of the AOF; use Redis backups for full data recovery."
        static let repairRuntimeServicesConfirmation = "Restarts the VM, guest log sync, host proxy, and watchdog services. VitalServer may be briefly unavailable while services restart."
        static let startRuntimeServicesConfirmation = "Starts the VM, host proxy, and watchdog services, then waits for VitalServer to become healthy."
        static let stopRuntimeServicesConfirmation = "Stops the watchdog, host proxy, and VM services. VitalServer will be unavailable until runtime services are started again."
        static let standardUninstallConfirmation = "Creates a Redis backup first, then removes the Helper app, runtime services, tools, VM disk, and package receipt. Logs, backups, Redis backups, and Vital files are preserved. If Redis backup creation fails, uninstall is stopped."
        static let cleanUninstallConfirmation = "Removes the Helper app, runtime services, tools, VM disk, logs, backups, Redis backups, package receipt, and configured Vital files directory."
        static let deleteBackupConfirmation = "Delete the selected managed backup? This cannot be undone."
        static let bridgedModeUnavailable = "Bridged mode is not available in this build."
        static let diskDecreaseUnavailable = "Disk size can only be increased."
        static let vitalFilesDirectoryRequired = "Vital files directory must be an absolute path."
        static let vitalFilesDirectoryProtected = "Vital files directory cannot be Desktop, Documents, Downloads, or iCloud Drive. Choose a non-protected local folder such as /Users/Shared/TiroshVitalServer/vital-files."
        static let invalidPort = "Port must be between 1 and 65535."
        static let invalidRedisBackupRetention = "Redis backups must be between 1 and 30 archives."
        static let adminPasswordRequired = "Admin password reset value must not be empty."
        static let adminPasswordNewline = "Admin password reset value must not contain newlines."
        static func commandFailed(exitCode: Int32) -> String {
            "Command failed with exit code \(exitCode)"
        }

        static func installState(installed isInstalled: Bool) -> String {
            isInstalled ? installed : notInstalled
        }

        static func launchdState(loaded: Bool) -> String {
            loaded ? running : stopped
        }

        static func vmState(_ value: RuntimeVMState?) -> String {
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

        static func vmError(_ value: RuntimeVMError) -> String {
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
            case .guestBootstrapMissingRuntimePackages:
                return "Guest bootstrap missing runtime packages"
            case .guestBootstrapFailed:
                return "Guest bootstrap failed"
            case .unknown(let rawValue):
                return titleCasedStatus(rawValue)
            }
        }

        static func failureReason(_ value: RuntimeFailureReason) -> String {
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
            case .guestRuntimeStateStale:
                return "Guest runtime state stale"
            case .auditProxyHTTP(let status):
                return "Audit proxy HTTP \(status)"
            case .containerService(let service, let state):
                return "Container \(service) \(titleCasedStatus(state))"
            case .vitalDBAnomaly(let kind, let subject):
                return "VitalDB anomaly \(titleCasedStatus(kind)) on \(subject)"
            case .proxyPortInUse(let port, let listeners):
                return "Host proxy port \(port) in use by \(listeners)"
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

        static func domainRecoveryAction(_ value: RuntimeDomainRecoveryAction) -> String {
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

        static func domainError(_ value: RuntimeFailureReason) -> String {
            "\(failureReason(value)) (\(domainRecoveryAction(value.recoveryAction)))"
        }

        static func reachability(httpStatus: String?) -> String {
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

        static func runtimeLifecycle(_ rawValue: String?) -> String {
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

        static func operation(_ rawValue: String?) -> String {
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

        static func progressStepStatus(_ rawValue: String) -> String {
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

        static func containerHealth(_ rawValue: String?) -> String {
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

        static func containerState(_ rawValue: String?) -> String {
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

    enum Notifications {
        static let needsAttentionTitle = "VitalServer needs attention"
        static let criticalTitle = "VitalServer is critical"
        static let recoveredTitle = "VitalServer recovered"
        static let needsAttentionBody = "Open VitalServer Helper to review runtime health details."
        static let criticalBody = "VitalServer runtime requires administrator attention."
        static let recoveredBody = "All monitored runtime services are healthy again."
    }

}
