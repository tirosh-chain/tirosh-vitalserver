import Application
import Bootstrap
import Foundation
import Infrastructure

typealias RuntimeHealthCheckerContext = Infrastructure.RuntimeHealthCheckerContext
typealias RuntimeHealthChecker = Infrastructure.RuntimeHealthChecker

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
