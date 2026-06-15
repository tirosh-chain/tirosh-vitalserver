import Application
import Bootstrap
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
        plistBuddyPath: String,
        lsofPath: String,
        curlPath: String,
        now: @escaping @Sendable () -> Date = Date.init
    ) -> RuntimeHealthChecker {
        return RuntimeHealthChecker(
            context: context(
                installedPaths: installedPaths,
                plistBuddyPath: plistBuddyPath,
                lsofPath: lsofPath,
                curlPath: curlPath
            ),
            fileStore: fileStore,
            serviceManager: serviceManager,
            commandRunner: commandRunner,
            httpProber: httpProber,
            guestGateway: guestGateway,
            now: now
        )
    }

    public static func context(
        installedPaths: InstalledRuntimePaths,
        plistBuddyPath: String,
        lsofPath: String,
        curlPath: String
    ) -> RuntimeHealthCheckerContext {
        RuntimeHealthCheckerContext(
            installedPaths: installedPaths,
            vmExecutablePath: Constants.InstallPaths.vmBin,
            proxyExecutablePath: Constants.InstallPaths.proxyRun,
            rootfsBaseURL: installedPaths.runtimeDirectory.appendingPathComponent(Constants.Artifacts.rootfsBase),
            vmDiskURL: installedPaths.runtimeDirectory.appendingPathComponent(Constants.BootAssets.disk),
            plistBuddyPath: plistBuddyPath,
            lsofPath: lsofPath,
            curlPath: curlPath,
            proxyLaunchDaemonPlist: RuntimeManagedServicePaths.launchDaemonPlist(.proxy),
            runtimeStateStaleAfterSeconds: Constants.Runtime.runtimeStateStaleAfterSeconds,
            watchdogManagedOperationGraceSeconds: Constants.Runtime.watchdogManagedOperationGraceSeconds,
            proxyHealthURL: { Constants.Runtime.proxyHealthURL(port: $0) },
            redisUIHealthURL: { Constants.Runtime.redisUIHealthURL(port: $0) },
            swaggerUIHealthURL: { Constants.Runtime.swaggerUIHealthURL(port: $0) },
            auditProxyStatusURL: { Constants.Runtime.auditProxyStatusURL(port: $0) }
        )
    }
}
