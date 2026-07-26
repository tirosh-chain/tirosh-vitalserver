import Contracts
import Foundation
import Errors

public struct RuntimeStatusPrinterCurrentStatus {
    let status: RuntimeStatusLevel
    let vmIP: String?

    public init(status: RuntimeStatusLevel, vmIP: String?) {
        self.status = status
        self.vmIP = vmIP
    }
}

public struct RuntimeStatusPrinter {
    let productRoot: URL
    let runtimeDirectory: URL
    let runtimeStatus: URL
    let launcherPath: String
    let proxyRunnerPath: String
    let rootfsBase: URL
    let vmDisk: URL
    let latestBackupPath: () throws -> String?
    let currentStatus: () -> RuntimeStatusPrinterCurrentStatus
    let runtimeVersionValue: () -> String
    let installedProxyPort: () -> Int?
    let hostProxyHTTP: (Int) -> String
    let fileStateAtPath: (String) -> RuntimeFileState
    let fileStateAtURL: (URL) -> RuntimeFileState
    let serviceState: (RuntimeManagedService) -> RuntimeServiceState
    let printLine: (String) -> Void

    public init(
        productRoot: URL,
        runtimeDirectory: URL,
        runtimeStatus: URL,
        launcherPath: String,
        proxyRunnerPath: String,
        rootfsBase: URL,
        vmDisk: URL,
        latestBackupPath: @escaping () throws -> String?,
        currentStatus: @escaping () -> RuntimeStatusPrinterCurrentStatus,
        runtimeVersionValue: @escaping () -> String,
        installedProxyPort: @escaping () -> Int?,
        hostProxyHTTP: @escaping (Int) -> String,
        fileStateAtPath: @escaping (String) -> RuntimeFileState,
        fileStateAtURL: @escaping (URL) -> RuntimeFileState,
        serviceState: @escaping (RuntimeManagedService) -> RuntimeServiceState,
        printLine: @escaping (String) -> Void = { print($0) }
    ) {
        self.productRoot = productRoot
        self.runtimeDirectory = runtimeDirectory
        self.runtimeStatus = runtimeStatus
        self.launcherPath = launcherPath
        self.proxyRunnerPath = proxyRunnerPath
        self.rootfsBase = rootfsBase
        self.vmDisk = vmDisk
        self.latestBackupPath = latestBackupPath
        self.currentStatus = currentStatus
        self.runtimeVersionValue = runtimeVersionValue
        self.installedProxyPort = installedProxyPort
        self.hostProxyHTTP = hostProxyHTTP
        self.fileStateAtPath = fileStateAtPath
        self.fileStateAtURL = fileStateAtURL
        self.serviceState = serviceState
        self.printLine = printLine
    }

    public func printStatus() {
        printLine("Tirosh VitalServer runtime")
        printLine("  product root: \(productRoot.path)")
        printLine("  runtime dir: \(runtimeDirectory.path)")
        printLine("  latest backup: \(latestBackupText())")
        printLine("  status diagnostics file: \(fileState(url: runtimeStatus))")
        let currentStatus = currentStatus()
        printLine("  status: \(currentStatus.status.rawValue)")
        printLine("  launcher: \(fileState(path: launcherPath))")
        printLine("  proxy runner: \(fileState(path: proxyRunnerPath))")
        printLine("  rootfs base: \(fileState(url: rootfsBase))")
        printLine("  vm disk: \(fileState(url: vmDisk))")
        printLine("  version: \(runtimeVersionValue())")
        printLine("  VM service: \(serviceState(.vm).rawValue)")
        printLine("  proxy service: \(serviceState(.proxy).rawValue)")
        printLine("  watchdog service: \(serviceState(.watchdog).rawValue)")
        printLine("  VM IP: \(currentStatus.vmIP ?? "not reported")")
        if let proxyPort = installedProxyPort() {
            printLine("  proxy port: \(proxyPort)")
            printLine("  host proxy HTTP: \(hostProxyHTTP(proxyPort))")
        } else {
            printLine("  proxy port: not reported")
            printLine("  host proxy HTTP: \(RuntimeHTTPStatusText.missingProxyPort)")
        }
    }

    private func fileState(path: String) -> String {
        fileStateAtPath(path).rawValue
    }

    private func fileState(url: URL) -> String {
        fileStateAtURL(url).rawValue
    }

    private func latestBackupText() -> String {
        do {
            return try latestBackupPath() ?? "none"
        } catch {
            return "read failed: \(error.localizedDescription)"
        }
    }
}
