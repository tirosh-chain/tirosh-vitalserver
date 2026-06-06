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
        guestGateway: RuntimeGuestGateway,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self = RuntimeHealthCheckerComposition.make(
            installedPaths: installedPaths,
            fileStore: fileStore,
            serviceManager: serviceManager,
            commandRunner: commandRunner,
            httpProber: httpProber,
            guestGateway: guestGateway,
            now: now
        )
    }
}
