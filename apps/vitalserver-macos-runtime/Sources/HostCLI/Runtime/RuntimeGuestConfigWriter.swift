import Foundation
import Core
import Contracts
import HostInfrastructure

struct RuntimeGuestConfigWriter {
    let installedPaths: InstalledRuntimePaths
    let fileStore: RuntimeFileStore
    var restrictSecretFile: (URL) throws -> Void

    func writeInstallConfig(settings: InstallSettings) throws {
        let document = GuestRuntimeConfigDocument(
            vitalserverHttpPort: Constants.Guest.vitalserverHTTPPort,
            redisHost: Constants.Guest.redisHost,
            redisPort: Constants.Guest.redisPort,
            trustProxy: true,
            publicHost: settings.publicHost,
            publicPort: settings.publicPort,
            adminPassword: settings.adminPassword ?? Constants.Guest.defaultAdminPassword,
            vitalFilesDirectory: Constants.Defaults.vitalFilesDirectoryGuestMountPath,
            redisBackupRetentionCount: Constants.Defaults.redisBackupRetentionCount,
            redisUiPort: Constants.Guest.redisUIPort,
            swaggerUiPort: Constants.Guest.swaggerUIPort
        )
        let runtimeConfig = installedPaths.guestRuntimeConfig
        let data = try JSONEncoder.pretty.encode(document)
        try fileStore.writeData(data, to: runtimeConfig, options: .atomic)
        try restrictSecretFile(runtimeConfig)
    }
}
