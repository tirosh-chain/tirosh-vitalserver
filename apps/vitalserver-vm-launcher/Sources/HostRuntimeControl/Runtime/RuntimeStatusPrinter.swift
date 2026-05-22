import Foundation

struct RuntimeStatusPrinter {
    let productRoot: URL
    let runtimeDirectory: URL
    let runtimeStatus: URL
    let rootfsBase: URL
    let vmDisk: URL
    let latestBackupPath: () -> String?
    let runtimeStatusValue: () -> String
    let runtimeVersionValue: () -> String
    let vmIP: () -> String
    let installedProxyPort: () -> Int
    let hostProxyHTTP: (Int) -> String
    let isExecutableFile: (String) -> Bool
    let fileExists: (URL) -> Bool
    let serviceState: (String) -> String
    let printLine: (String) -> Void

    init(
        productRoot: URL,
        runtimeDirectory: URL,
        runtimeStatus: URL,
        rootfsBase: URL,
        vmDisk: URL,
        latestBackupPath: @escaping () -> String?,
        runtimeStatusValue: @escaping () -> String,
        runtimeVersionValue: @escaping () -> String,
        vmIP: @escaping () -> String,
        installedProxyPort: @escaping () -> Int,
        hostProxyHTTP: @escaping (Int) -> String,
        isExecutableFile: @escaping (String) -> Bool,
        fileExists: @escaping (URL) -> Bool,
        serviceState: @escaping (String) -> String,
        printLine: @escaping (String) -> Void = { print($0) }
    ) {
        self.productRoot = productRoot
        self.runtimeDirectory = runtimeDirectory
        self.runtimeStatus = runtimeStatus
        self.rootfsBase = rootfsBase
        self.vmDisk = vmDisk
        self.latestBackupPath = latestBackupPath
        self.runtimeStatusValue = runtimeStatusValue
        self.runtimeVersionValue = runtimeVersionValue
        self.vmIP = vmIP
        self.installedProxyPort = installedProxyPort
        self.hostProxyHTTP = hostProxyHTTP
        self.isExecutableFile = isExecutableFile
        self.fileExists = fileExists
        self.serviceState = serviceState
        self.printLine = printLine
    }

    func printStatus() {
        printLine("Tirosh VitalServer runtime")
        printLine("  product root: \(productRoot.path)")
        printLine("  runtime dir: \(runtimeDirectory.path)")
        printLine("  latest backup: \(latestBackupPath() ?? "none")")
        printLine("  status file: \(fileState(url: runtimeStatus))")
        printLine("  status: \(runtimeStatusValue())")
        printLine("  launcher: \(fileState(path: Constants.InstallPaths.vmBin))")
        printLine("  proxy runner: \(fileState(path: Constants.InstallPaths.proxyRun))")
        printLine("  rootfs base: \(fileState(url: rootfsBase))")
        printLine("  vm disk: \(fileState(url: vmDisk))")
        printLine("  version: \(runtimeVersionValue())")
        printLine("  VM service: \(serviceState(Constants.Launchd.vmService))")
        printLine("  proxy service: \(serviceState(Constants.Launchd.proxyService))")
        printLine("  watchdog service: \(serviceState(Constants.Launchd.watchdogService))")
        printLine("  VM IP: \(vmIP())")
        let proxyPort = installedProxyPort()
        printLine("  proxy port: \(proxyPort)")
        printLine("  host proxy HTTP: \(hostProxyHTTP(proxyPort))")
    }

    private func fileState(path: String) -> String {
        if isExecutableFile(path) {
            return "executable"
        }
        if fileExists(URL(fileURLWithPath: path)) {
            return "present"
        }
        return "missing"
    }

    private func fileState(url: URL) -> String {
        fileExists(url) ? "present" : "missing"
    }
}
