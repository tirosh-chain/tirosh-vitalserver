import Foundation
import Bootstrap
import Contracts
import OutboundAdapters
@testable import CLIHost
import XCTest
import Errors

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
        let runtimeConfig = makeRuntimeConfig(
            publicHost: "vital.example.test",
            publicPort: 8080,
            adminPassword: "custom-secret"
        )

        try writer.write(runtimeConfig: runtimeConfig)

        let data = try XCTUnwrap(fileStore.files[paths.guestRuntimeConfig])
        let document = try JSONDecoder().decode(GuestRuntimeConfigDocument.self, from: data)
        XCTAssertEqual(document.vitalserverHttpPort, Constants.Guest.vitalserverHTTPPort)
        XCTAssertEqual(document.redisHost, Constants.Guest.redisHost)
        XCTAssertEqual(document.redisPort, Constants.Guest.redisPort)
        XCTAssertEqual(document.publicHost, "vital.example.test")
        XCTAssertEqual(document.publicPort, 8080)
        XCTAssertEqual(document.adminPassword, "custom-secret")
        XCTAssertEqual(document.vitalFilesDirectory, Constants.Defaults.vitalFilesDirectoryGuestMountPath)
        let settingsData = try XCTUnwrap(fileStore.files[paths.guestRuntimeSettings])
        let settingsDocument = try JSONDecoder().decode(GuestRuntimeSettingsDocument.self, from: settingsData)
        XCTAssertEqual(settingsDocument.publicHost, "vital.example.test")
        XCTAssertEqual(settingsDocument.publicPort, 8080)
        XCTAssertEqual(settingsDocument.automaticBackupEnabled, true)
        XCTAssertEqual(settingsDocument.backupScheduleTimes, ["03:15"])
        XCTAssertEqual(settingsDocument.backupRetentionCount, Constants.Defaults.backupRetentionCount)
        XCTAssertEqual(restricted, [paths.guestRuntimeConfig])
    }

    func testWriteInstallConfigWritesExplicitDefaultAdminPassword() throws {
        let fileStore = RuntimeFileStoreSpy()
        let paths = InstalledRuntimePaths(productRoot: URL(fileURLWithPath: "/product"))
        let writer = RuntimeGuestConfigWriter(
            installedPaths: paths,
            fileStore: fileStore,
            restrictSecretFile: { _ in }
        )

        try writer.write(runtimeConfig: makeRuntimeConfig(adminPassword: Constants.Guest.defaultAdminPassword))

        let data = try XCTUnwrap(fileStore.files[paths.guestRuntimeConfig])
        let document = try JSONDecoder().decode(GuestRuntimeConfigDocument.self, from: data)
        XCTAssertEqual(document.adminPassword, Constants.Guest.defaultAdminPassword)
    }

    private func makeRuntimeConfig(
        publicHost: String = "",
        publicPort: Int = Constants.Guest.publicPort,
        adminPassword: String
    ) -> GuestRuntimeConfigDocument {
        GuestRuntimeConfigDocument(
            vitalserverHttpPort: Constants.Guest.vitalserverHTTPPort,
            redisHost: Constants.Guest.redisHost,
            redisPort: Constants.Guest.redisPort,
            trustProxy: true,
            vitalServerURL: "",
            remoteConsoleURL: "",
            publicHost: publicHost,
            publicPort: publicPort,
            adminPassword: adminPassword,
            vitalFilesDirectory: Constants.Defaults.vitalFilesDirectoryGuestMountPath,
            redisUiPort: Constants.Guest.redisUIPort,
            swaggerUiPort: Constants.Guest.swaggerUIPort
        )
    }
}
