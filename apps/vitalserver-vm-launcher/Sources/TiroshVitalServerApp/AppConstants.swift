enum AppConstants {
    enum Product {
        static let displayName = "Tirosh VitalServer Manager"
        static let subtitle = "Manage the Mac mini runtime"
        static let vitalServerURL = "http://127.0.0.1/"
        static let redisUIURL = "http://127.0.0.1/redis-ui/"
        static let swaggerURL = "http://127.0.0.1/swagger/"
        static let hostProxyHealthURL = "http://127.0.0.1:80/"
        static func guestHealthURL(vmIP: String) -> String {
            "http://\(vmIP)/"
        }
    }

    enum Labels {
        static let runtime = "Runtime"
        static let vmService = "VM service"
        static let proxyService = "Proxy service"
        static let vmIP = "VM IP"
        static let guestHTTP = "Guest HTTP"
        static let hostProxy = "Host proxy"
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
        static let failed = "failed"
        static let done = "Done"
        static let healthCheckCompleted = "Health check completed"
        static let missingUninstaller = "Missing uninstaller"
        static let uninstallPreparing = "Preparing runtime removal..."
        static let uninstallWaitingForPrivilege = "Waiting for administrator approval..."
        static let uninstallRunning = "Removing runtime..."
        static let uninstallCompleted = "Runtime removal completed."
        static let commandCancelled = "Command was cancelled or failed."
        static func commandFailed(exitCode: Int32) -> String {
            "Command failed with exit code \(exitCode)"
        }
    }

    enum Paths {
        static let launcher = "/usr/local/bin/vitalserver-vm"
        static let uninstaller = "/usr/local/bin/tirosh-vitalserver-uninstall"
        static let vmIPFile = "/Library/Application Support/TiroshVitalServer/vm/data/run/vm-ip"
        static let commandLogFile = "/private/tmp/tirosh-vitalserver-manager-command.log"
    }

    enum Launchd {
        static let vmService = "com.tirosh.vitalserver-vm"
        static let proxyService = "com.tirosh.vitalserver-proxy"
    }

    enum Commands {
        static let osascript = "/usr/bin/osascript"
        static let curl = "/usr/bin/curl"
        static let launchctl = "/bin/launchctl"
    }
}
