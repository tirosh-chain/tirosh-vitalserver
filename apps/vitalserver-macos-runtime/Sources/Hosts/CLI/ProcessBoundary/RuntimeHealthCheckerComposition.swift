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
        plistBuddyPath: String,
        lsofPath: String,
        curlPath: String,
        guestAddressProvider: (any RuntimeGuestAddressProvider)? = nil,
        vmLifecycleResourceReader: (any RuntimeVMLifecycleResourceReading)? = nil,
        guestControlGateway: (@Sendable () throws -> any RuntimeGuestControlGateway)? = nil,
        guestControlGatewayForBaseURL: (@Sendable (String) throws -> any RuntimeGuestControlGateway)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) -> RuntimeHealthChecker {
        let resolvedGuestAddressProvider = guestAddressProvider ?? RuntimeControlAPIGuestAddressProvider()
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
            guestAddressProvider: resolvedGuestAddressProvider,
            vmLifecycleResourceReader: vmLifecycleResourceReader,
            guestControlGateway: guestControlGateway,
            guestControlGatewayForBaseURL: guestControlGatewayForBaseURL,
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
            watchdogManagedOperationGraceSeconds: Constants.Runtime.watchdogManagedOperationGraceSeconds,
            proxyHealthURL: { Constants.Runtime.proxyHealthURL(port: $0) },
            redisUIHealthURL: { Constants.Runtime.redisUIHealthURL(port: $0) },
            swaggerUIHealthURL: { Constants.Runtime.swaggerUIHealthURL(port: $0) }
        )
    }
}
