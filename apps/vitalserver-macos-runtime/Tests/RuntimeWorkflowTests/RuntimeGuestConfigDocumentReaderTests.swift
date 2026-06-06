import Application
import Contracts
import Foundation
import Infrastructure
import XCTest

final class RuntimeGuestConfigDocumentReaderTests: XCTestCase {
    func testLoadReportsMissingFileAsTypedInfrastructureError() {
        let fileStore = FileReaderStub()
        let url = URL(fileURLWithPath: "/guest/runtime-config.json")

        XCTAssertThrowsError(try RuntimeGuestConfigDocumentReader.load(from: url, fileStore: fileStore)) { error in
            XCTAssertEqual(
                error as? RuntimeGuestConfigDocumentReadError,
                .missingFile("/guest/runtime-config.json")
            )
        }
    }

    func testLoadDecodesCurrentDocument() throws {
        let url = URL(fileURLWithPath: "/guest/runtime-config.json")
        let document = makeRuntimeConfig(vitalServerURL: "https://vitaldb.tirosh.ai/")
        let fileStore = FileReaderStub(files: [url: try JSONEncoder().encode(document)])

        let loaded = try RuntimeGuestConfigDocumentReader.load(from: url, fileStore: fileStore)

        XCTAssertEqual(loaded, document)
    }

    func testLoadDecodesLegacyDocumentThroughContractMigration() throws {
        let url = URL(fileURLWithPath: "/guest/runtime-config.json")
        let legacyJSON = """
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
        let fileStore = FileReaderStub(files: [url: Data(legacyJSON.utf8)])

        let loaded = try RuntimeGuestConfigDocumentReader.load(from: url, fileStore: fileStore)

        XCTAssertEqual(loaded.vitalServerURL, "http://vitaldb.tirosh.ai:8080/")
        XCTAssertEqual(loaded.remoteConsoleURL, "")
    }

    private func makeRuntimeConfig(vitalServerURL: String) -> GuestRuntimeConfigDocument {
        GuestRuntimeConfigDocument(
            vitalserverHttpPort: 18080,
            redisHost: "redis",
            redisPort: 6379,
            trustProxy: true,
            vitalServerURL: vitalServerURL,
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
    }
}

private final class FileReaderStub: RuntimeFileReading {
    var files: [URL: Data]

    init(files: [URL: Data] = [:]) {
        self.files = files
    }

    func fileExists(_ url: URL) -> Bool {
        files[url] != nil
    }

    func directoryExists(_ url: URL) -> Bool {
        false
    }

    func isExecutableFile(atPath path: String) -> Bool {
        false
    }

    func readData(_ url: URL) throws -> Data {
        guard let data = files[url] else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return data
    }

    func readUTF8Text(_ url: URL) throws -> String {
        String(decoding: try readData(url), as: UTF8.self)
    }

    func fileSize(_ url: URL) throws -> UInt64 {
        UInt64(try readData(url).count)
    }

    func modificationDate(_ url: URL) throws -> Date {
        Date(timeIntervalSince1970: 0)
    }
}
