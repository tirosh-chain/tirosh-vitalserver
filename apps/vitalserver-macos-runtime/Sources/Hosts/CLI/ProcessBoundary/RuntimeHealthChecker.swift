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
        guestBootstrapResultReader: any RuntimeGuestBootstrapResultReader,
        guestAddressProvider: (any RuntimeGuestAddressProvider)? = nil,
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
            guestBootstrapResultReader: guestBootstrapResultReader,
            plistBuddyPath: Constants.Commands.plistBuddy,
            lsofPath: Constants.Commands.lsof,
            curlPath: Constants.Commands.curl,
            guestAddressProvider: guestAddressProvider,
            guestControlGateway: guestControlGateway,
            guestControlGatewayForBaseURL: guestControlGatewayForBaseURL,
            now: now
        )
    }
}
