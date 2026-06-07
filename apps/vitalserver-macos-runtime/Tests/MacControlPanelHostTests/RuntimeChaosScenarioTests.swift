import Contracts
import Application
import Domain
import Foundation
import RuntimeControl
@testable import OutboundAdapters
import XCTest
import Errors
@testable import InboundAdapters

final class RuntimeChaosScenarioTests: XCTestCase {
    func testCommandLogReadDoesNotDependOnCentralLogCollectionPermission() {
        let collector = ChaosFailingRuntimeLogCollector()
        let reader = SystemRuntimeHostFileReader(
            fileStore: ChaosCommandLogFileStore(
                textByPath: [
                    RuntimeControlClientConstants.Paths.commandLogFile: "first\nsecond\nthird",
                ]
            ),
            logCollector: collector
        )

        let logResult = reader.logTextResult(sourceID: RuntimeLogSource.command, lineLimit: 2)

        XCTAssertEqual(logResult, .loaded("second\nthird"))
        XCTAssertEqual(collector.sourceIDs, [])
        XCTAssertEqual(collector.refreshCount, 0)
    }

    func testObservabilityReadChaosReturnsReadErrorInsteadOfEmptySuccess() {
        let reader = SystemRuntimeObservabilityReader.live(
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

    func testObservabilityReadChaosDoesNotCreateSQLiteReadModel() throws {
        let root = try temporaryDirectory()
        defer { cleanup(root) }
        let statusDirectory = root.appendingPathComponent("status", isDirectory: true)
        let events = root.appendingPathComponent(RuntimeFileNames.runtimeEvents)
        let database = statusDirectory.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB)
        let event = RuntimeEventDocument(
            id: "jsonl-event",
            eventType: .statusChanged,
            timestamp: "2026-05-31T00:00:00Z",
            product: "VitalServerHelper",
            status: .healthy,
            previousStatus: nil,
            operation: .health,
            message: "ready",
            runtimeVersion: "1.2.3",
            failureReasons: [],
            containerObservation: nil,
            progress: nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try (encoder.encode(event) + Data("\n".utf8)).write(to: events)
        let reader = SystemRuntimeObservabilityReader.live(
            paths: RuntimePaths(
                runtimeEvents: events.path,
                runtimeObservabilityDB: database.path
            )
        )

        let eventHistory = reader.loadRuntimeEvents(limit: 10)
        let recorderHistory = reader.loadVitalDBRecorders()
        let relationships = reader.loadVitalDBRelationships()

        XCTAssertEqual(eventHistory.events.map(\.id), ["jsonl-event"])
        XCTAssertNotNil(eventHistory.readError)
        XCTAssertEqual(recorderHistory.activityHistory.source, .unavailable)
        XCTAssertNotNil(recorderHistory.readError)
        XCTAssertNotNil(recorderHistory.activityHistory.readError)
        XCTAssertNotNil(relationships.readError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: statusDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: database.path))
    }

    func testObservabilitySnapshotChaosReturnsFailedStateInsteadOfUnavailableDefault() {
        let reader = SystemRuntimeObservabilityReader.live(
            paths: RuntimePaths(
                runtimeState: "/dev/null/\(RuntimeFileNames.runtimeState)",
                runtimeStatus: "/dev/null/\(RuntimeFileNames.runtimeStatus)",
                runtimeObservabilityDB: "/dev/null/\(RuntimeFileNames.runtimeObservabilityDB)"
            )
        )

        let snapshot = reader.loadVitalDBObservationSnapshot()

        XCTAssertEqual(snapshot.state, .failed)
        XCTAssertNil(snapshot.observation)
        XCTAssertNotNil(snapshot.readError)
        XCTAssertFalse(snapshot.readError?.isEmpty == true)
    }

    func testObservabilityRelationshipChaosPreservesBothReadFailures() {
        let reader = SystemRuntimeObservabilityReader.live(
            paths: RuntimePaths(runtimeObservabilityDB: "/dev/null/\(RuntimeFileNames.runtimeObservabilityDB)")
        )

        let history = reader.loadVitalDBRelationships()

        XCTAssertEqual(history.assignments, [])
        XCTAssertEqual(history.events, [])
        XCTAssertTrue(history.readError?.contains("assignments=") == true)
        XCTAssertTrue(history.readError?.contains("events=") == true)
    }

    func testLogExportChaosRecordsCollectionAndSupplementalIssuesInManifest() async throws {
        let root = try temporaryDirectory()
        defer { cleanup(root) }
        let productLogs = root.appendingPathComponent("product/logs", isDirectory: true)
        let source = root.appendingPathComponent("runtime-config.json")
        let destination = root.appendingPathComponent("export.zip")
        try FileManager.default.createDirectory(at: productLogs, withIntermediateDirectories: true)
        try "secret".write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: source.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: source.path)
        }

        var archivedManifest: RuntimeLogExportManifest?
        let exporter = MacRuntimeControlLogExporter(
            logCollector: ChaosFailingExportLogCollector(),
            productLogsDirectory: productLogs,
            supplementalLogItems: [
                RuntimeLogExportSupplementalSource(
                    source: source,
                    relativeDestination: "diagnostics/guest/runtime-config.json"
                ),
            ],
            rotatedSupplementalSets: [],
            archiveRunner: { _, arguments in
                let bundleRoot = URL(fileURLWithPath: arguments[4])
                let temporaryArchive = URL(fileURLWithPath: arguments[5])
                if let manifestData = try? Data(
                    contentsOf: bundleRoot.appendingPathComponent("diagnostics/export-manifest.json")
                ) {
                    archivedManifest = try? JSONDecoder().decode(RuntimeLogExportManifest.self, from: manifestData)
                }
                try? "archive".write(to: temporaryArchive, atomically: true, encoding: .utf8)
                return RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
            }
        )

        _ = try await exporter.exportLogs(to: destination)

        XCTAssertEqual(archivedManifest?.collectionIssue, "collection denied")
        let item = try XCTUnwrap(archivedManifest?.supplementalItems.first)
        XCTAssertTrue(item.sourcePresent)
        XCTAssertFalse(item.included)
        XCTAssertEqual(item.status, "failed")
        XCTAssertNotNil(item.error)
    }

    func testObservabilityCorruptionChaosReturnsReadErrorInsteadOfEmptySuccess() throws {
        let root = try temporaryDirectory()
        defer { cleanup(root) }
        let database = root.appendingPathComponent(RuntimeFileNames.runtimeObservabilityDB)
        try "not a sqlite database".write(to: database, atomically: true, encoding: .utf8)
        let reader = SystemRuntimeObservabilityReader.live(
            paths: RuntimePaths(
                runtimeState: root.appendingPathComponent(RuntimeFileNames.runtimeState).path,
                runtimeStatus: root.appendingPathComponent(RuntimeFileNames.runtimeStatus).path,
                runtimeObservabilityDB: database.path
            )
        )

        let snapshot = reader.loadVitalDBObservationSnapshot()
        let relationships = reader.loadVitalDBRelationships()

        XCTAssertEqual(snapshot.state, .failed)
        XCTAssertNotNil(snapshot.readError)
        XCTAssertEqual(relationships.assignments, [])
        XCTAssertEqual(relationships.events, [])
        XCTAssertTrue(relationships.readError?.contains("assignments=") == true)
        XCTAssertTrue(relationships.readError?.contains("events=") == true)
    }

    func testInstalledPermissionChaosPropagatesBackupReadDeniedInsteadOfEmptyList() {
        let reader = SystemRuntimeHostFileReader(
            fileStore: ChaosPermissionFileStore(),
            logCollector: ChaosFailingRuntimeLogCollector()
        )

        XCTAssertThrowsError(try reader.backups(latestBackupPath: nil)) { error in
            XCTAssertEqual((error as NSError).code, CocoaError.Code.fileReadNoPermission.rawValue)
        }
    }

    func testCleanUninstallResidueChaosStopsAtMissingUninstallerBoundary() async {
        let runner = ChaosPrivilegedCommandRunner()
        let worker = MacRuntimeControlCommandWorker(
            privilegedCommandRunner: runner,
            actionEnvironment: ChaosActionEnvironment(executablePaths: []),
            logExporter: ChaosNoopLogExporter()
        )

        do {
            _ = try await worker.uninstallRuntime(clean: true)
            XCTFail("Expected missing uninstaller")
        } catch {
            XCTAssertEqual((error as? RuntimeClientError)?.errorDescription, RuntimeControlClientConstants.StatusText.missingUninstaller)
        }
        XCTAssertEqual(runner.commands, [])
    }

    func testSettingsPermissionChaosDoesNotSurfaceSecretRuntimeConfigAsRequiredReadModel() {
        let reader = SystemRuntimeSettingsReader(
            paths: RuntimeSettingsPaths(
                vmConfig: "/missing/vm-config.json",
                vmDisk: "/missing/vm-disk.img",
                guestRuntimeSettings: "/missing/runtime-settings.json",
                proxyLaunchDaemon: "/missing/proxy.plist"
            ),
            fileStore: ChaosPermissionFileStore()
        )

        let settings = reader.load()

        XCTAssertFalse(settings.readIssues.contains { $0.source == "guestRuntimeConfig" })
        XCTAssertTrue(settings.readIssues.contains { $0.source == "guestRuntimeSettings" })
        XCTAssertEqual(settings.publicHost, RuntimeSettings().publicHost)
        XCTAssertEqual(settings.publicPort, RuntimeSettings().publicPort)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeChaosScenarioTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
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

private final class ChaosFailingExportLogCollector: RuntimeLogCollecting, @unchecked Sendable {
    func refreshLogCollection() throws {
        throw NSError(
            domain: "RuntimeChaosScenarioTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "collection denied"]
        )
    }

    func refreshLogCollection(sourceID: RuntimeLogSource) throws {
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

private final class ChaosPermissionFileStore: RuntimeFileStore {
    var temporaryDirectory = URL(fileURLWithPath: "/tmp")
    private let secretConfig: URL?

    init(secretConfig: URL? = nil) {
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
    func childDirectories(at url: URL, nameContains fragment: String, skipsHiddenFiles: Bool) throws -> [URL] {
        throw CocoaError(.fileReadNoPermission)
    }
    func recursiveRegularFileSize(at url: URL, skipsHiddenFiles: Bool) throws -> UInt64 { 0 }
    func fileSystemAttributes(forPath path: String) throws -> RuntimeFileSystemAttributes {
        RuntimeFileSystemAttributes(freeBytes: 1)
    }
}

private final class ChaosPrivilegedCommandRunner: PrivilegedCommandRunning, @unchecked Sendable {
    private(set) var commands: [String] = []

    func run(shellCommand: String) async -> RuntimeCommandResult {
        commands.append(shellCommand)
        return RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
    }
}

private struct ChaosActionEnvironment: RuntimeActionEnvironment {
    let executablePaths: Set<String>

    init(executablePaths: Set<String>) {
        self.executablePaths = executablePaths
    }

    func executableState(atPath path: String) -> RuntimeFileState {
        executablePaths.contains(path) ? .executable : .missing
    }

    func writeAdminPasswordFile(_ password: String) throws -> URL {
        URL(fileURLWithPath: "/tmp/admin-password")
    }

    func removeItem(at url: URL) throws {}

    func verifyBundle(launcher: String, bundleURL: URL) async -> RuntimeCommandResult {
        RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
    }
}

private struct ChaosNoopLogExporter: RuntimeLogExporting {
    func exportLogs(to destination: URL) async throws -> RuntimeLogExportResult {
        RuntimeLogExportResult(destination: destination)
    }
}
