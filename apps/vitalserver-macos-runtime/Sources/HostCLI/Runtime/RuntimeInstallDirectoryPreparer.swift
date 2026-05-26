import Foundation
import Core
import Contracts
import HostInfrastructure

struct RuntimeInstallDirectoryPreparer {
    let installedPaths: InstalledRuntimePaths
    let fileStore: RuntimeFileStore
    var now: () -> Date

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
        try migrateLegacyRuntimeLogsToCentral()
    }

    private func migrateLegacyRuntimeLogsToCentral() throws {
        let legacyDirectory = installedPaths.logsDirectory
        let centralRuntimeLogsDirectory = installedPaths.centralRuntimeLogsDirectory
        guard legacyDirectory != centralRuntimeLogsDirectory,
              fileStore.directoryExists(legacyDirectory)
        else {
            return
        }

        let entries = (try? fileStore.contentsOfDirectory(at: legacyDirectory, skipsHiddenFiles: false)) ?? []
        for entry in entries where fileStore.fileExists(entry) {
            let destination = uniqueLogMigrationURL(
                centralRuntimeLogsDirectory.appendingPathComponent(entry.lastPathComponent)
            )
            try fileStore.moveItem(at: entry, to: destination)
        }

        if ((try? fileStore.contentsOfDirectory(at: legacyDirectory, skipsHiddenFiles: false)) ?? []).isEmpty {
            try fileStore.removeItem(at: legacyDirectory)
        }
    }

    private func uniqueLogMigrationURL(_ url: URL) -> URL {
        guard fileStore.fileExists(url) else {
            return url
        }
        let timestamp = Int(now().timeIntervalSince1970)
        let migrated = url.deletingLastPathComponent()
            .appendingPathComponent("legacy-\(url.lastPathComponent).\(timestamp)")
        guard fileStore.fileExists(migrated) else {
            return migrated
        }
        for index in 1...999 {
            let candidate = url.deletingLastPathComponent()
                .appendingPathComponent("legacy-\(url.lastPathComponent).\(timestamp).\(index)")
            if !fileStore.fileExists(candidate) {
                return candidate
            }
        }
        return url.deletingLastPathComponent()
            .appendingPathComponent("legacy-\(url.lastPathComponent).\(timestamp).\(UUID().uuidString)")
    }
}
