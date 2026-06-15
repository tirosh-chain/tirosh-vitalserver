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
    let latestBackupPath: () throws -> String?
    let runtimeStatusDocument: () -> RuntimeStatusDocumentLoadResult
    let runtimeVersionValue: () -> String
    let installedProxyPort: () -> Int?
    let hostProxyHTTPStatus: (String) -> String
    let fileStateAtPath: (String) -> RuntimeFileState
    let fileStateAtURL: (URL) -> RuntimeFileState
    let serviceState: (RuntimeManagedService) -> RuntimeServiceState
    let printLine: (String) -> Void

    public init(
        latestBackupPath: @escaping () throws -> String?,
        runtimeStatusDocument: @escaping () -> RuntimeStatusDocumentLoadResult,
        runtimeVersionValue: @escaping () -> String,
        installedProxyPort: @escaping () -> Int?,
        hostProxyHTTPStatus: @escaping (String) -> String,
        fileStateAtPath: @escaping (String) -> RuntimeFileState,
        fileStateAtURL: @escaping (URL) -> RuntimeFileState,
        serviceState: @escaping (RuntimeManagedService) -> RuntimeServiceState,
        printLine: @escaping (String) -> Void = { print($0) }
    ) {
        self.latestBackupPath = latestBackupPath
        self.runtimeStatusDocument = runtimeStatusDocument
        self.runtimeVersionValue = runtimeVersionValue
        self.installedProxyPort = installedProxyPort
        self.hostProxyHTTPStatus = hostProxyHTTPStatus
        self.fileStateAtPath = fileStateAtPath
        self.fileStateAtURL = fileStateAtURL
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
            runtimeStatusDocument: operations.runtimeStatusDocument,
            runtimeVersionValue: operations.runtimeVersionValue,
            installedProxyPort: operations.installedProxyPort,
            hostProxyHTTP: { port in
                operations.hostProxyHTTPStatus(Constants.Runtime.proxyHealthURL(port: port))
            },
            fileStateAtPath: operations.fileStateAtPath,
            fileStateAtURL: operations.fileStateAtURL,
            serviceState: operations.serviceState,
            printLine: operations.printLine
        )
    }
}
