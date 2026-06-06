import Contracts
import XCTest
import Errors

final class GuestRuntimeConfigDocumentTests: XCTestCase {
    func testDecodesGuestRuntimeConfigDocument() throws {
        let json = """
        {
          "vitalserverHttpPort": 18080,
          "redisHost": "redis",
          "redisPort": 6379,
          "trustProxy": true,
          "vitalServerURL": "https://vitaldb.tirosh.ai/",
          "remoteConsoleURL": "https://console.tirosh.ai/",
          "publicHost": "vitaldb.tirosh.ai",
          "publicPort": 443,
          "adminPassword": "admin",
          "vitalFilesDirectory": "/mnt/tirosh-vital-files",
          "redisBackupRetentionCount": 20,
          "redisUiPort": 18081,
          "swaggerUiPort": 18082,
          "testkitEnabled": false
        }
        """

        let document = try JSONDecoder().decode(GuestRuntimeConfigDocument.self, from: Data(json.utf8))

        XCTAssertEqual(document.vitalserverHttpPort, 18080)
        XCTAssertEqual(document.vitalServerURL, "https://vitaldb.tirosh.ai/")
        XCTAssertEqual(document.remoteConsoleURL, "https://console.tirosh.ai/")
        XCTAssertEqual(document.publicHost, "vitaldb.tirosh.ai")
        XCTAssertEqual(document.publicPort, 443)
        XCTAssertEqual(document.redisBackupRetentionCount, 20)
        XCTAssertFalse(document.testkitEnabled)
    }

    func testDecodeRequiresExplicitAdvertisedURLs() {
        let json = """
        {
          "vitalserverHttpPort": 18080,
          "redisHost": "redis",
          "redisPort": 6379,
          "trustProxy": true,
          "publicHost": "vitaldb.tirosh.ai",
          "publicPort": 8080,
          "adminPassword": "admin",
          "vitalFilesDirectory": "/mnt/tirosh-vital-files",
          "redisBackupRetentionCount": 20,
          "redisUiPort": 18081,
          "swaggerUiPort": 18082,
          "testkitEnabled": false
        }
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(GuestRuntimeConfigDocument.self, from: Data(json.utf8))
        )
    }

    func testMigrationDecodesLegacyVitalServerURLFromExplicitPublicHostAndPort() throws {
        let json = """
        {
          "vitalserverHttpPort": 18080,
          "redisHost": "redis",
          "redisPort": 6379,
          "trustProxy": true,
          "publicHost": "vitaldb.tirosh.ai",
          "publicPort": 8080,
          "adminPassword": "admin",
          "vitalFilesDirectory": "/mnt/tirosh-vital-files",
          "redisBackupRetentionCount": 20,
          "redisUiPort": 18081,
          "swaggerUiPort": 18082,
          "testkitEnabled": false
        }
        """

        let document = try GuestRuntimeConfigDocumentMigration.decodeCurrentOrLegacy(Data(json.utf8))

        XCTAssertEqual(document.vitalServerURL, "http://vitaldb.tirosh.ai:8080/")
        XCTAssertEqual(document.remoteConsoleURL, "")
    }

    func testRequiresExplicitGuestRuntimeConfigFields() {
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

    func testBuildsGuestRuntimeSettingsDocumentFromRuntimeConfig() {
        let runtimeConfig = GuestRuntimeConfigDocument(
            vitalserverHttpPort: 18080,
            redisHost: "redis",
            redisPort: 6379,
            trustProxy: true,
            vitalServerURL: "https://vitaldb.tirosh.ai/",
            remoteConsoleURL: "https://console.tirosh.ai/",
            publicHost: "vitaldb.tirosh.ai",
            publicPort: 443,
            adminPassword: "admin",
            vitalFilesDirectory: "/mnt/tirosh-vital-files",
            redisBackupRetentionCount: 20,
            redisUiPort: 18081,
            swaggerUiPort: 18082,
            testkitEnabled: false
        )

        let document = GuestRuntimeSettingsDocument(runtimeConfig: runtimeConfig)

        XCTAssertEqual(document.vitalServerURL, "https://vitaldb.tirosh.ai/")
        XCTAssertEqual(document.remoteConsoleURL, "https://console.tirosh.ai/")
        XCTAssertEqual(document.publicHost, "vitaldb.tirosh.ai")
        XCTAssertEqual(document.publicPort, 443)
        XCTAssertEqual(document.redisBackupRetentionCount, 20)
    }
}
