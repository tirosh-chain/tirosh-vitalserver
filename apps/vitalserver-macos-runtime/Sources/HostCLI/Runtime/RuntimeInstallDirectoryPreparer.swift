import Foundation
import Core
import Contracts
import HostInfrastructure

struct RuntimeInstallDirectoryPreparer {
    let installedPaths: InstalledRuntimePaths
    let fileStore: RuntimeFileStore

    func prepare(settings: InstallSettings) throws {
        let directories = [
            installedPaths.runtimeDirectory,
            URL(fileURLWithPath: settings.vitalFilesDirectory),
            installedPaths.deployDirectory,
            installedPaths.guestRunDirectory,
            installedPaths.vrReleaseDirectory,
            installedPaths.backupsDirectory,
            installedPaths.redisBackupsDirectory,
            installedPaths.productLogsDirectory,
            installedPaths.centralRuntimeLogsDirectory,
            installedPaths.centralGuestLogsDirectory,
            installedPaths.logArchiveDirectory,
            installedPaths.hostRunDirectory,
            installedPaths.statusDirectory,
            installedPaths.nginxLogsDirectory,
        ]
        for directory in directories {
            try fileStore.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
