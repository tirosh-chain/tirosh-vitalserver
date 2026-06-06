import Bootstrap
import Contracts
import Foundation
import OutboundAdapters
import InboundAdapters
import Errors

public struct RuntimeStatusPrinterCompositionContext {
    let productRoot: URL
    let installedPaths: InstalledRuntimePaths
    let rootfsBase: URL
    let vmDisk: URL

    public init(
        productRoot: URL,
        installedPaths: InstalledRuntimePaths,
        rootfsBase: URL,
        vmDisk: URL
    ) {
        self.productRoot = productRoot
        self.installedPaths = installedPaths
        self.rootfsBase = rootfsBase
        self.vmDisk = vmDisk
    }
}

public struct RuntimeStatusPrinterCompositionOperations {
    let latestBackupPath: () -> String?
    let runtimeStatusValue: () -> String?
    let runtimeVersionValue: () -> String
    let vmIP: () -> String
    let installedProxyPort: () -> Int
    let hostProxyHTTPStatus: (String) -> String
    let isExecutableFile: (String) -> Bool
    let fileExists: (URL) -> Bool
    let serviceState: (RuntimeManagedService) -> RuntimeServiceState
    let printLine: (String) -> Void

    public init(
        latestBackupPath: @escaping () -> String?,
        runtimeStatusValue: @escaping () -> String?,
        runtimeVersionValue: @escaping () -> String,
        vmIP: @escaping () -> String,
        installedProxyPort: @escaping () -> Int,
        hostProxyHTTPStatus: @escaping (String) -> String,
        isExecutableFile: @escaping (String) -> Bool,
        fileExists: @escaping (URL) -> Bool,
        serviceState: @escaping (RuntimeManagedService) -> RuntimeServiceState,
        printLine: @escaping (String) -> Void = { print($0) }
    ) {
        self.latestBackupPath = latestBackupPath
        self.runtimeStatusValue = runtimeStatusValue
        self.runtimeVersionValue = runtimeVersionValue
        self.vmIP = vmIP
        self.installedProxyPort = installedProxyPort
        self.hostProxyHTTPStatus = hostProxyHTTPStatus
        self.isExecutableFile = isExecutableFile
        self.fileExists = fileExists
        self.serviceState = serviceState
        self.printLine = printLine
    }
}

public enum RuntimeStatusPrinterComposition {
    public static func make(
        context: RuntimeStatusPrinterCompositionContext,
        operations: RuntimeStatusPrinterCompositionOperations
    ) -> RuntimeStatusPrinter {
        RuntimeStatusPrinter(
            productRoot: context.productRoot,
            runtimeDirectory: context.installedPaths.runtimeDirectory,
            runtimeStatus: context.installedPaths.runtimeStatus,
            launcherPath: Constants.InstallPaths.vmBin,
            proxyRunnerPath: Constants.InstallPaths.proxyRun,
            rootfsBase: context.rootfsBase,
            vmDisk: context.vmDisk,
            latestBackupPath: operations.latestBackupPath,
            runtimeStatusValue: operations.runtimeStatusValue,
            runtimeVersionValue: operations.runtimeVersionValue,
            vmIP: operations.vmIP,
            installedProxyPort: operations.installedProxyPort,
            hostProxyHTTP: { port in
                operations.hostProxyHTTPStatus(Constants.Runtime.proxyHealthURL(port: port))
            },
            isExecutableFile: operations.isExecutableFile,
            fileExists: operations.fileExists,
            serviceState: operations.serviceState,
            printLine: operations.printLine
        )
    }
}
