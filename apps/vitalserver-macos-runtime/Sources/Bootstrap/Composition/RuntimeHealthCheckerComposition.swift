import Application
import Contracts
import Foundation
import OutboundAdapters
import Errors

public enum RuntimeHealthCheckerComposition {
    public static func make(
        installedPaths: InstalledRuntimePaths,
        fileStore: RuntimeFileStore,
        serviceManager: RuntimeServiceManager,
        commandRunner: RuntimeCommandRunner,
        httpProber: RuntimeHTTPProber,
        guestGateway: RuntimeGuestGateway,
        now: @escaping @Sendable () -> Date = Date.init
    ) -> RuntimeHealthChecker {
        RuntimeHealthChecker(
            context: context(installedPaths: installedPaths),
            fileStore: fileStore,
            serviceManager: serviceManager,
            commandRunner: commandRunner,
            httpProber: httpProber,
            guestGateway: guestGateway,
            now: now
        )
    }

    public static func context(installedPaths: InstalledRuntimePaths) -> RuntimeHealthCheckerContext {
        RuntimeHealthCheckerContext(
            installedPaths: installedPaths,
            vmExecutablePath: Constants.InstallPaths.vmBin,
            proxyExecutablePath: Constants.InstallPaths.proxyRun,
            rootfsBaseURL: installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase),
            vmDiskURL: installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk),
            plistBuddyPath: Constants.Commands.plistBuddy,
            lsofPath: Constants.Commands.lsof,
            curlPath: Constants.Commands.curl,
            proxyLaunchDaemonPlist: RuntimeManagedServicePaths.launchDaemonPlist(.proxy),
            defaultProxyPort: Constants.Guest.publicPort,
            runtimeStateStaleAfterSeconds: Constants.Runtime.runtimeStateStaleAfterSeconds,
            watchdogManagedOperationGraceSeconds: Constants.Runtime.watchdogManagedOperationGraceSeconds,
            proxyHealthURL: { Constants.Runtime.proxyHealthURL(port: $0) },
            redisUIHealthURL: { Constants.Runtime.redisUIHealthURL(port: $0) },
            swaggerUIHealthURL: { Constants.Runtime.swaggerUIHealthURL(port: $0) },
            auditProxyStatusURL: { Constants.Runtime.auditProxyStatusURL(port: $0) }
        )
    }
}
