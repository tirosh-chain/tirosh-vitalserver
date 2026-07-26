import Application
import Bootstrap
import Foundation
import OutboundAdapters
import Errors

extension RuntimeHealthChecker {
    init(
        installedPaths: InstalledRuntimePaths,
        fileStore: RuntimeFileStore,
        serviceManager: RuntimeServiceManager,
        commandRunner: RuntimeCommandRunner,
        httpProber: RuntimeHTTPProber,
        guestAddressProvider: (any RuntimeGuestAddressProvider)? = nil,
        vmLifecycleResourceReader: (any RuntimeVMLifecycleResourceReading)? = nil,
        guestControlGateway: (@Sendable () throws -> any RuntimeGuestControlGateway)? = nil,
        guestControlGatewayForBaseURL: (@Sendable (String) throws -> any RuntimeGuestControlGateway)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self = RuntimeHealthCheckerComposition.make(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: serviceManager,
            commandRunner: commandRunner,
            httpProber: httpProber,
            plistBuddyPath: Constants.Commands.plistBuddy,
            lsofPath: Constants.Commands.lsof,
            curlPath: Constants.Commands.curl,
            guestAddressProvider: guestAddressProvider,
            vmLifecycleResourceReader: vmLifecycleResourceReader,
            guestControlGateway: guestControlGateway,
            guestControlGatewayForBaseURL: guestControlGatewayForBaseURL,
            now: now
        )
    }
}
