import Foundation
import Core
import Contracts
import HostInfrastructure

struct RuntimeGuestConfigWriter {
    let installedPaths: InstalledRuntimePaths
    let fileStore: RuntimeFileStore
    var restrictSecretFile: (URL) throws -> Void

    func writeInstallConfig(settings: InstallSettings) throws {
        guard let adminPassword = settings.adminPassword else {
            throw LauncherError.missingArgument("install settings adminPassword is required")
        }
        let document = GuestRuntimeConfigDocument(
            vitalserverHttpPort: Constants.Guest.vitalserverHTTPPort,
            redisHost: Constants.Guest.redisHost,
            redisPort: Constants.Guest.redisPort,
            trustProxy: true,
            vitalServerURL: settings.vitalServerURL,
            remoteConsoleURL: settings.remoteConsoleURL,
            publicHost: settings.publicHost,
            publicPort: settings.publicPort,
            adminPassword: adminPassword,
            vitalFilesDirectory: Constants.Defaults.vitalFilesDirectoryGuestMountPath,
            redisBackupRetentionCount: Constants.Defaults.redisBackupRetentionCount,
            redisUiPort: Constants.Guest.redisUIPort,
            swaggerUiPort: Constants.Guest.swaggerUIPort,
            testkitEnabled: Constants.testkitContainerIncluded
        )
        let runtimeConfig = installedPaths.guestRuntimeConfig
        let data = try JSONEncoder.pretty.encode(document)
        try fileStore.writeData(data, to: runtimeConfig, options: .atomic)
        try writeSettings(document)
        try restrictSecretFile(runtimeConfig)
    }

    private func writeSettings(_ runtimeConfig: GuestRuntimeConfigDocument) throws {
        let document = GuestRuntimeSettingsDocument(runtimeConfig: runtimeConfig)
        try fileStore.writeData(
            try JSONEncoder.pretty.encode(document),
            to: installedPaths.guestRuntimeSettings,
            options: .atomic
        )
    }
}
