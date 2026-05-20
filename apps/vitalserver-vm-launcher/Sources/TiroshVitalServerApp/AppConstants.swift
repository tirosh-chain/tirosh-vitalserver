enum AppConstants {
    enum Product {
        static let displayName = "Tirosh VitalServer Manager"
        static let subtitle = "Install and manage the Mac mini runtime"
        static let bundledPackageName = "TiroshVitalServerVM"
        static let bundledPackageExtension = "pkg"
        static let bundledUninstallerName = "tirosh-vitalserver-uninstall"
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
        static let installProfile = "Runtime Profile"
        static let storage = "Resources"
        static let network = "Network"
        static let data = "Data"
        static let account = "Account"
        static let advanced = "Advanced"
        static let service = "Service"
        static let review = "Review"
    }

    enum Actions {
        static let installRuntime = "Install Runtime"
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
        static let missingBundledPackage = "Missing bundled runtime package"
        static let missingUninstaller = "Missing uninstaller"
        static let installAlreadyPresent = "Runtime is already installed. Uninstall first if you want a clean reinstall."
        static let installWizardIntro = "Choose the initial runtime settings before installation."
        static let installSettingsCaptured = "Install settings selected."
        static let installSettingsWriteFailed = "Failed to write install settings."
        static let installPreparing = "Preparing runtime installation..."
        static let installWaitingForPrivilege = "Waiting for administrator approval..."
        static let installRunning = "Installing runtime. This can take several minutes while the VM disk is unpacked."
        static let installCompleted = "Runtime installation completed."
        static let installWaitingForRuntime = "Package installed. Waiting for VM runtime readiness..."
        static let installReady = "Runtime is ready."
        static let installReadinessTimedOut = "Runtime was installed, but readiness check timed out. Use Health Check or inspect launchd logs."
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
        static let installSettingsFile = "/private/tmp/tirosh-vitalserver-install.env"
        static let commandLogFile = "/private/tmp/tirosh-vitalserver-manager-command.log"
    }

    enum Launchd {
        static let vmService = "com.tirosh.vitalserver-vm"
        static let proxyService = "com.tirosh.vitalserver-proxy"
    }

    enum Commands {
        static let osascript = "/usr/bin/osascript"
        static let installer = "/usr/sbin/installer"
        static let curl = "/usr/bin/curl"
        static let launchctl = "/bin/launchctl"
    }

    enum InstallWizard {
        static let recommendedProfile = "Recommended"
        static let customProfile = "Custom"
        static let sharedNetwork = "Shared/NAT + host proxy"
        static let bridgedNetwork = "Bridged LAN"
        static let bridgedUnavailable = "Bridged mode requires Apple entitlement approval and is not enabled in this build."
        static let hostProxyPort = "Host proxy port"
        static let sharedNetworkAddressing = "Shared/NAT mode assigns the VM IP automatically. Users and VRecorder devices connect through the Mac host proxy port."
        static let vitalFilesDirectory = "Vital files directory"
        static let choose = "Choose..."
        static let vitalFilesDirectoryDescription = "Only .vital files are stored under this directory. Runtime files such as deploy, run, and VR release stay in the managed application support directory."
        static let adminPassword = "Admin password"
        static let confirmAdminPassword = "Confirm admin password"
        static let adminPasswordDescription = "This becomes the initial VitalServer admin password. It is not shown in the review step."
        static let adminPasswordMismatch = "Admin password and confirmation do not match."
        static let adminPasswordRequired = "Admin password is required."
        static let vmHostname = "VM hostname"
        static let publicHost = "Public host"
        static let publicPort = "Public port"
        static let publicHostDescription = "Optional. Use this only when VitalServer must advertise a fixed host name or IP to browser clients."
        static let advancedDescription = "These settings are applied during first installation. Leave them as-is unless the deployment network requires them."
        static let startAfterInstall = "Start runtime after install"
        static let startOnBoot = "Start runtime on boot"
        static let diskSize = "Disk"
        static let cpu = "CPU"
        static let memory = "Memory"
        static let cpuRequirement = "VitalServer requires at least 7 vCPU. 8 vCPU is recommended."
        static let recommendedResourcesLocked = "Recommended uses the Mac mini operating default. Choose Custom on the previous step to tune resources."
    }
}
