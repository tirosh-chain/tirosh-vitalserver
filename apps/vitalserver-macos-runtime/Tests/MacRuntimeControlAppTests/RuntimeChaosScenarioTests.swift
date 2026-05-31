import Contracts
import Core
import Foundation
import RuntimeControl
@testable import MacHostRuntimeAdapter
import XCTest

final class RuntimeChaosScenarioTests: XCTestCase {
    func testUpdateLogRefreshChaosKeepsReadableCommandLogVisible() {
        let collector = ChaosFailingRuntimeLogCollector()
        let reader = SystemRuntimeHostFileReader(
            fileStore: ChaosCommandLogFileStore(
                textByPath: [
                    RuntimeAdapterConstants.Paths.commandLogFile: "first\nsecond\nthird",
                ]
            ),
            logCollector: collector
        )

        let logText = reader.logText(sourceID: RuntimeLogSource.command, helperMessage: "Ready", lineLimit: 2)

        XCTAssertEqual(logText, "second\nthird")
        XCTAssertEqual(collector.sourceIDs, [.command])
        XCTAssertEqual(collector.refreshCount, 1)
    }

    func testObservabilityReadChaosReturnsReadErrorInsteadOfEmptySuccess() {
        let reader = SystemRuntimeObservabilityReader(
            paths: RuntimePaths(
                runtimeEvents: "/dev/null/\(RuntimeFileNames.runtimeEvents)",
                runtimeObservabilityDB: "/dev/null/\(RuntimeFileNames.runtimeObservabilityDB)"
            )
        )

        let history = reader.loadRuntimeEvents(limit: 50)

        XCTAssertEqual(history.events, [])
        XCTAssertEqual(history.matchingCount, 0)
        XCTAssertNotNil(history.readError)
        XCTAssertFalse(history.readError?.isEmpty == true)
    }

    func testSettingsPermissionChaosDoesNotSurfaceSecretRuntimeConfigAsRequiredReadModel() {
        let secretConfig = URL(fileURLWithPath: "/product/vm/data/deploy/runtime-config.json")
        let reader = SystemRuntimeSettingsReader(
            paths: RuntimeSettingsPaths(
                vmConfig: "/missing/vm-config.json",
                vmDisk: "/missing/vm-disk.img",
                guestRuntimeSettings: "/missing/runtime-settings.json",
                guestRuntimeConfig: secretConfig.path,
                proxyLaunchDaemon: "/missing/proxy.plist"
            ),
            fileStore: ChaosSecretRuntimeConfigFileStore(secretConfig: secretConfig)
        )

        let settings = reader.load()

        XCTAssertFalse(settings.readIssues.contains { $0.source == "guestRuntimeConfig" })
        XCTAssertEqual(settings.publicHost, RuntimeSettings().publicHost)
        XCTAssertEqual(settings.publicPort, RuntimeSettings().publicPort)
    }
}

private final class ChaosFailingRuntimeLogCollector: RuntimeLogCollecting, @unchecked Sendable {
    private(set) var refreshCount = 0
    private(set) var sourceIDs: [RuntimeLogSource] = []

    func refreshLogCollection() throws {
        refreshCount += 1
        throw CocoaError(.fileReadNoPermission)
    }

    func refreshLogCollection(sourceID: RuntimeLogSource) throws {
        sourceIDs.append(sourceID)
        try refreshLogCollection()
    }
}

private final class ChaosCommandLogFileStore: RuntimeFileStore, RuntimeFilePartialReading {
    var temporaryDirectory = URL(fileURLWithPath: "/tmp")
    private let textByPath: [String: String]

    init(textByPath: [String: String]) {
        self.textByPath = textByPath
    }

    func fileExists(_ url: URL) -> Bool {
        textByPath[url.path] != nil
    }

    func directoryExists(_ url: URL) -> Bool { false }
    func isExecutableFile(atPath path: String) -> Bool { false }

    func readData(_ url: URL) throws -> Data {
        guard let text = textByPath[url.path] else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return Data(text.utf8)
    }

    func readData(_ url: URL, offset: UInt64?) throws -> Data {
        let data = try readData(url)
        guard let offset else {
            return data
        }
        return data.suffix(from: min(Int(offset), data.count))
    }

    func readUTF8Text(_ url: URL) throws -> String {
        String(decoding: try readData(url), as: UTF8.self)
    }

    func fileSize(_ url: URL) throws -> UInt64 {
        UInt64(try readData(url).count)
    }

    func modificationDate(_ url: URL) throws -> Date { Date(timeIntervalSince1970: 0) }
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws {}
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions, posixPermissions: Int) throws {}
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {}
    func removeItem(at url: URL) throws {}
    func copyItem(at source: URL, to destination: URL) throws {}
    func moveItem(at source: URL, to destination: URL) throws {}
    func contentsOfDirectory(at url: URL, skipsHiddenFiles: Bool) throws -> [URL] { [] }
    func childDirectories(at url: URL, nameContains fragment: String, skipsHiddenFiles: Bool) throws -> [URL] { [] }
    func recursiveRegularFileSize(at url: URL, skipsHiddenFiles: Bool) throws -> UInt64 { 0 }
    func fileSystemAttributes(forPath path: String) throws -> RuntimeFileSystemAttributes {
        RuntimeFileSystemAttributes(freeBytes: 1)
    }
}

private final class ChaosSecretRuntimeConfigFileStore: RuntimeFileStore {
    var temporaryDirectory = URL(fileURLWithPath: "/tmp")
    private let secretConfig: URL

    init(secretConfig: URL) {
        self.secretConfig = secretConfig
    }

    func fileExists(_ url: URL) -> Bool {
        url == secretConfig
    }

    func directoryExists(_ url: URL) -> Bool { false }
    func isExecutableFile(atPath path: String) -> Bool { false }

    func readData(_ url: URL) throws -> Data {
        if url == secretConfig {
            throw CocoaError(.fileReadNoPermission)
        }
        throw CocoaError(.fileReadNoSuchFile)
    }

    func readUTF8Text(_ url: URL) throws -> String {
        String(decoding: try readData(url), as: UTF8.self)
    }

    func fileSize(_ url: URL) throws -> UInt64 { throw CocoaError(.fileReadNoSuchFile) }
    func modificationDate(_ url: URL) throws -> Date { throw CocoaError(.fileReadNoSuchFile) }
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws {}
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions, posixPermissions: Int) throws {}
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {}
    func removeItem(at url: URL) throws {}
    func copyItem(at source: URL, to destination: URL) throws {}
    func moveItem(at source: URL, to destination: URL) throws {}
    func contentsOfDirectory(at url: URL, skipsHiddenFiles: Bool) throws -> [URL] { [] }
    func childDirectories(at url: URL, nameContains fragment: String, skipsHiddenFiles: Bool) throws -> [URL] { [] }
    func recursiveRegularFileSize(at url: URL, skipsHiddenFiles: Bool) throws -> UInt64 { 0 }
    func fileSystemAttributes(forPath path: String) throws -> RuntimeFileSystemAttributes {
        RuntimeFileSystemAttributes(freeBytes: 1)
    }
}
