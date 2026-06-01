import Foundation
import HostInfrastructure
@testable import HostCLI
import XCTest

final class RuntimeGuestConfigWriterTests: XCTestCase {
    func testWriteInstallConfigWritesGuestConfigAndRestrictsFile() throws {
        let fileStore = RuntimeFileStoreSpy()
        let paths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        var restricted: [URL] = []
        let writer = RuntimeGuestConfigWriter(
            installedPaths: paths,
            fileStore: fileStore,
            restrictSecretFile: { url in
                restricted.append(url)
            }
        )
        var settings = InstallSettings(vitalFilesDirectory: "/custom/vital-files")
        settings.publicHost = "vital.example.test"
        settings.publicPort = 8080
        settings.adminPassword = "custom-secret"

        try writer.writeInstallConfig(settings: settings)

        let data = try XCTUnwrap(fileStore.files[paths.guestRuntimeConfig])
        let document = try JSONDecoder().decode(GuestRuntimeConfigDocument.self, from: data)
        XCTAssertEqual(document.vitalserverHttpPort, Constants.Guest.vitalserverHTTPPort)
        XCTAssertEqual(document.redisHost, Constants.Guest.redisHost)
        XCTAssertEqual(document.redisPort, Constants.Guest.redisPort)
        XCTAssertEqual(document.publicHost, "vital.example.test")
        XCTAssertEqual(document.publicPort, 8080)
        XCTAssertEqual(document.adminPassword, "custom-secret")
        XCTAssertEqual(document.vitalFilesDirectory, Constants.Defaults.vitalFilesDirectoryGuestMountPath)
        XCTAssertEqual(document.redisBackupRetentionCount, Constants.Defaults.redisBackupRetentionCount)
        let settingsData = try XCTUnwrap(fileStore.files[paths.guestRuntimeSettings])
        let settingsDocument = try JSONDecoder().decode(GuestRuntimeSettingsDocument.self, from: settingsData)
        XCTAssertEqual(settingsDocument.publicHost, "vital.example.test")
        XCTAssertEqual(settingsDocument.publicPort, 8080)
        XCTAssertEqual(settingsDocument.redisBackupRetentionCount, Constants.Defaults.redisBackupRetentionCount)
        XCTAssertEqual(restricted, [paths.guestRuntimeConfig])
    }

    func testWriteInstallConfigUsesDefaultAdminPasswordWhenSettingsOmitIt() throws {
        let fileStore = RuntimeFileStoreSpy()
        let paths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let writer = RuntimeGuestConfigWriter(
            installedPaths: paths,
            fileStore: fileStore,
            restrictSecretFile: { _ in }
        )

        try writer.writeInstallConfig(settings: InstallSettings(vitalFilesDirectory: "/custom/vital-files"))

        let data = try XCTUnwrap(fileStore.files[paths.guestRuntimeConfig])
        let document = try JSONDecoder().decode(GuestRuntimeConfigDocument.self, from: data)
        XCTAssertEqual(document.adminPassword, Constants.Guest.defaultAdminPassword)
    }

    func testGuestRuntimeConfigRequiresExplicitHostOwnedFields() throws {
        let json = """
        {
          "vitalserverHttpPort": 18080,
          "redisHost": "redis",
          "redisPort": 6379,
          "trustProxy": true,
          "publicHost": "",
          "publicPort": 80,
          "adminPassword": "admin",
          "vitalFilesDirectory": "/mnt/tirosh-vital-files",
          "redisUiPort": 18081,
          "swaggerUiPort": 18082
        }
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(GuestRuntimeConfigDocument.self, from: Data(json.utf8))
        )
    }
}
