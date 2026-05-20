enum AppConstants {
    enum Product {
        static let displayName = "Tirosh VitalServer Manager"
        static let subtitle = "Manage the dedicated Mac runtime"
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
        static func hostProxyHealthURL(proxyPort: Int) -> String {
            "http://127.0.0.1:\(proxyPort)/"
        }
        static func guestHealthURL(vmIP: String) -> String {
            "http://\(vmIP)/"
        }
    }

    enum Labels {
        static let runtime = "Runtime"
        static let runtimeState = "Runtime state"
        static let operation = "Operation"
        static let runtimeVersion = "Runtime version"
        static let updatedAt = "Updated at"
        static let vmService = "VM service"
        static let proxyService = "Proxy service"
        static let watchdogService = "Watchdog service"
        static let proxyPort = "Proxy port"
        static let vmIP = "VM IP"
        static let guestHTTP = "Guest HTTP"
        static let hostProxy = "Host proxy"
        static let failureReasons = "Failure reasons"
        static let log = "Log"
    }

    enum Actions {
        static let healthCheck = "Health Check"
        static let open = "Open"
        static let openVitalServer = "VitalServer"
        static let openRedisUI = "Redis UI"
        static let openSwagger = "Swagger"
        static let uninstall = "Uninstall"
        static let refresh = "Refresh"
        static let saveSettings = "Save Settings"
        static let chooseBundle = "Choose Bundle"
        static let applyBundle = "Apply Bundle"
        static let rollback = "Rollback"
        static let openLogs = "Open Logs"
        static let cancel = "Cancel"
        static let continueAction = "Continue"
        static let back = "Back"
        static let install = "Install"
    }

    enum StatusText {
        static let ready = "Ready"
        static let installed = "Installed"
        static let notInstalled = "Not installed"
        static let loaded = "Loaded"
        static let notLoaded = "Not loaded"
        static let waiting = "Waiting"
        static let notChecked = "Not checked"
        static let unknown = "Unknown"
        static let failed = "failed"
        static let done = "Done"
        static let healthCheckCompleted = "Health check completed"
        static let missingUninstaller = "Missing uninstaller"
        static let uninstallPreparing = "Preparing runtime removal..."
        static let uninstallWaitingForPrivilege = "Waiting for administrator approval..."
        static let uninstallRunning = "Removing runtime..."
        static let uninstallCompleted = "Runtime removal completed."
        static let settingsSaved = "Runtime settings saved."
        static let updateBundleApplied = "Update bundle applied."
        static let rollbackCompleted = "Rollback completed."
        static let missingLauncher = "Missing runtime launcher"
        static let missingBundle = "Choose an update bundle first."
        static let commandCancelled = "Command was cancelled or failed."
        static func commandFailed(exitCode: Int32) -> String {
            "Command failed with exit code \(exitCode)"
        }
    }

    enum Paths {
        static let launcher = "/usr/local/bin/vitalserver-vm"
        static let uninstaller = "/usr/local/bin/tirosh-vitalserver-uninstall"
        static let vmIPFile = "/Library/Application Support/TiroshVitalServer/vm/data/run/vm-ip"
        static let runtimeStatus = "/Library/Application Support/TiroshVitalServer/status/runtime-status.json"
        static let installLog = "/Library/Application Support/TiroshVitalServer/logs/install.log"
        static let runtimeLogs = "/Library/Application Support/TiroshVitalServer/vm/logs"
        static let vmConfig = "/Library/Application Support/TiroshVitalServer/vm/runtime/vm-config.json"
        static let guestRuntimeConfig = "/Library/Application Support/TiroshVitalServer/vm/data/deploy/runtime-config.json"
        static let proxyLaunchDaemon = "/Library/LaunchDaemons/com.tirosh.vitalserver-proxy.plist"
        static let commandLogFile = "/private/tmp/tirosh-vitalserver-manager-command.log"
    }

    enum Launchd {
        static let vmService = "com.tirosh.vitalserver-vm"
        static let proxyService = "com.tirosh.vitalserver-proxy"
        static let watchdogService = "com.tirosh.vitalserver-watchdog"
    }

    enum Commands {
        static let osascript = "/usr/bin/osascript"
        static let curl = "/usr/bin/curl"
        static let launchctl = "/bin/launchctl"
    }
}
