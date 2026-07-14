import Foundation
import Contracts
import RuntimeControl
@testable import OutboundAdapters
@testable import MacControlPanelHost
import XCTest
import Errors
@testable import InboundAdapters

@MainActor
final class RuntimeLogExporterTests: XCTestCase {
    func testDefaultExportSupplementalSourcesIncludeDiagnosticStateFiles() {
        let destinations = Set(RuntimeLogExportSupplementalSource.defaultItems().map(\.relativeDestination))

        XCTAssertTrue(destinations.contains("diagnostics/status/\(RuntimeDiagnosticsArtifactFileNames.runtimeStatus)"))
        XCTAssertTrue(destinations.contains("diagnostics/host/runtime-state.sqlite"))
        XCTAssertTrue(destinations.contains("diagnostics/host/\(RuntimeDiagnosticsArtifactFileNames.hostRuntimeStateEvents)"))
        XCTAssertTrue(destinations.contains("diagnostics/host/\(RuntimeDiagnosticsArtifactFileNames.hostRuntimeState)"))
        XCTAssertTrue(destinations.contains("diagnostics/status/\(RuntimeDiagnosticsArtifactFileNames.runtimeEvents)"))
        XCTAssertTrue(destinations.contains("diagnostics/status/\(RuntimeDiagnosticsArtifactFileNames.runtimeObservabilityDB)"))
        XCTAssertTrue(destinations.contains("diagnostics/status/\(RuntimeDiagnosticsArtifactFileNames.runtimeObservabilityDB)-wal"))
        XCTAssertTrue(destinations.contains("diagnostics/status/\(RuntimeDiagnosticsArtifactFileNames.runtimeObservabilityDB)-shm"))
        XCTAssertTrue(destinations.contains("diagnostics/guest/\(RuntimeDiagnosticsArtifactFileNames.runtimeObservation)"))
        XCTAssertTrue(destinations.contains("diagnostics/guest/\(RuntimeBootstrapEvidenceFileNames.vmIP)"))
        XCTAssertTrue(destinations.contains("diagnostics/runtime/vm-config.json"))
        XCTAssertTrue(destinations.contains("diagnostics/runtime/runtime-version.json"))
        XCTAssertTrue(destinations.contains("diagnostics/guest/runtime-config.json"))
        XCTAssertTrue(destinations.contains("diagnostics/host/ai.tirosh.vitalserver.helper.proxy.plist"))
        XCTAssertTrue(destinations.contains("diagnostics/host/vitalserver-nginx.conf"))
        XCTAssertTrue(destinations.contains("guest/guest-observability"))
        XCTAssertTrue(destinations.contains("helper-message.log"))
    }

    func testDefaultRotatedExportSupplementalSourcesIncludeRuntimeEventHistory() {
        let runtimeEventSet = RuntimeLogExportRotatedSupplementalSet.defaultSets().first {
            $0.sourceFilePrefix == "\(RuntimeDiagnosticsArtifactFileNames.runtimeEvents)."
        }

        XCTAssertEqual(runtimeEventSet?.relativeDestinationDirectory, "diagnostics/status")
        XCTAssertEqual(runtimeEventSet?.destinationFilePrefix, "\(RuntimeDiagnosticsArtifactFileNames.runtimeEvents).")
    }

    func testExportUsesExplicitStagingIdentityAndGeneratedTimestamp() async throws {
        let root = try temporaryDirectory()
        let stagingRoot = root.appendingPathComponent("staging", isDirectory: true)
        let productLogs = root.appendingPathComponent("product/logs", isDirectory: true)
        let destination = root.appendingPathComponent("export.zip")
        let expectedWorkingRoot = stagingRoot.appendingPathComponent(
            "vitalserver-log-export-fixed-export-id",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: productLogs, withIntermediateDirectories: true)

        var archivedBundleRoot: URL?
        var archivedTemporaryArchive: URL?
        var archivedManifest: RuntimeLogExportManifest?
        let exporter = MacRuntimeControlLogExporter(
            logCollector: FakeRuntimeLogCollectorForExport(),
            productLogsDirectory: productLogs,
            supplementalLogItems: [],
            rotatedSupplementalSets: [],
            temporaryDirectory: stagingRoot,
            exportID: { "fixed-export-id" },
            generatedAt: { "2026-06-08T00:00:00Z" },
            archiveRunner: { _, arguments in
                let bundleRoot = URL(fileURLWithPath: arguments[4])
                let temporaryArchive = URL(fileURLWithPath: arguments[5])
                archivedBundleRoot = bundleRoot
                archivedTemporaryArchive = temporaryArchive
                if let manifestData = try? Data(
                    contentsOf: bundleRoot.appendingPathComponent("diagnostics/export-manifest.json")
                ) {
                    archivedManifest = try? JSONDecoder().decode(RuntimeLogExportManifest.self, from: manifestData)
                }
                try? "archive".write(to: temporaryArchive, atomically: true, encoding: .utf8)
                return RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
            }
        )

        let result = try await exporter.exportLogs(to: destination)

        XCTAssertEqual(result.destination, destination)
        XCTAssertEqual(archivedBundleRoot, expectedWorkingRoot.appendingPathComponent("vitalserver-logs", isDirectory: true))
        XCTAssertEqual(archivedTemporaryArchive, expectedWorkingRoot.appendingPathComponent("export.zip"))
        XCTAssertEqual(archivedManifest?.generatedAt, "2026-06-08T00:00:00Z")
        XCTAssertFalse(FileManager.default.fileExists(atPath: expectedWorkingRoot.path))
    }

    func testExportReportsStagingCleanupFailureWithoutHidingCompletedArchive() async throws {
        let root = try temporaryDirectory()
        let stagingRoot = root.appendingPathComponent("staging", isDirectory: true)
        let productLogs = root.appendingPathComponent("product/logs", isDirectory: true)
        let destination = root.appendingPathComponent("export.zip")
        let expectedWorkingRoot = stagingRoot.appendingPathComponent(
            "vitalserver-log-export-cleanup-fails",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: productLogs, withIntermediateDirectories: true)
        let fileManager = FailingRemoveFileManager(failingPath: expectedWorkingRoot.path)
        let exporter = MacRuntimeControlLogExporter(
            fileManager: fileManager,
            logCollector: FakeRuntimeLogCollectorForExport(),
            productLogsDirectory: productLogs,
            supplementalLogItems: [],
            rotatedSupplementalSets: [],
            temporaryDirectory: stagingRoot,
            exportID: { "cleanup-fails" },
            archiveRunner: { _, arguments in
                let temporaryArchive = URL(fileURLWithPath: arguments[5])
                try? "archive".write(to: temporaryArchive, atomically: true, encoding: .utf8)
                return RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
            }
        )

        let result = try await exporter.exportLogs(to: destination)

        XCTAssertEqual(result.destination, destination)
        XCTAssertEqual(try String(contentsOf: destination), "archive")
        XCTAssertTrue(result.cleanupIssue?.contains("staging cleanup failed path=\(expectedWorkingRoot.path)") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedWorkingRoot.path))
    }

    func testExportRefreshesCollectionAndIncludesSupplementalGuestLogs() async throws {
        let root = try temporaryDirectory()
        let guestRun = root.appendingPathComponent("vm/data/run", isDirectory: true)
        let productLogs = root.appendingPathComponent("product/logs", isDirectory: true)
        let destination = root.appendingPathComponent("export.zip")
        try FileManager.default.createDirectory(at: guestRun, withIntermediateDirectories: true)
        try "bootstrap".write(
            to: guestRun.appendingPathComponent("bootstrap.log"),
            atomically: true,
            encoding: .utf8
        )
        try "containers".write(
            to: guestRun.appendingPathComponent("container-logs.log"),
            atomically: true,
            encoding: .utf8
        )
        try "rotated".write(
            to: guestRun.appendingPathComponent("container-logs.log.1"),
            atomically: true,
            encoding: .utf8
        )

        let collector = FakeRuntimeLogCollectorForExport()
        var archivedBootstrapLog: String?
        var archivedContainerLog: String?
        var archivedRotatedContainerLog: String?
        var archivedManifest: RuntimeLogExportManifest?
        let exporter = MacRuntimeControlLogExporter(
            logCollector: collector,
            productLogsDirectory: productLogs,
            supplementalLogItems: [
                RuntimeLogExportSupplementalSource(
                    source: guestRun.appendingPathComponent("bootstrap.log"),
                    relativeDestination: "guest/bootstrap.log"
                ),
                RuntimeLogExportSupplementalSource(
                    source: guestRun.appendingPathComponent("container-logs.log"),
                    relativeDestination: "guest/container-logs.log"
                ),
            ],
            rotatedSupplementalSets: [
                RuntimeLogExportRotatedSupplementalSet(
                    sourceDirectory: guestRun,
                    sourceFilePrefix: "container-logs.log.",
                    relativeDestinationDirectory: "guest",
                    destinationFilePrefix: "container-logs.log."
                ),
            ],
            archiveRunner: { _, arguments in
                let bundleRoot = URL(fileURLWithPath: arguments[4])
                let temporaryArchive = URL(fileURLWithPath: arguments[5])
                archivedBootstrapLog = try? String(
                    contentsOf: bundleRoot.appendingPathComponent("guest/bootstrap.log")
                )
                archivedContainerLog = try? String(
                    contentsOf: bundleRoot.appendingPathComponent("guest/container-logs.log")
                )
                archivedRotatedContainerLog = try? String(
                    contentsOf: bundleRoot.appendingPathComponent("guest/container-logs.log.1")
                )
                if let manifestData = try? Data(
                    contentsOf: bundleRoot.appendingPathComponent("diagnostics/export-manifest.json")
                ) {
                    archivedManifest = try? JSONDecoder().decode(RuntimeLogExportManifest.self, from: manifestData)
                }
                try? "archive".write(to: temporaryArchive, atomically: true, encoding: .utf8)
                return RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
            }
        )

        let result = try await exporter.exportLogs(to: destination)

        XCTAssertEqual(result.destination, destination)
        XCTAssertEqual(collector.refreshCount, 1)
        XCTAssertEqual(try String(contentsOf: destination), "archive")
        XCTAssertEqual(archivedBootstrapLog, "bootstrap")
        XCTAssertEqual(archivedContainerLog, "containers")
        XCTAssertEqual(archivedRotatedContainerLog, "rotated")
        XCTAssertEqual(archivedManifest?.supplementalItems.count, 2)
        XCTAssertEqual(archivedManifest?.supplementalItems.map(\.included), [true, true])
        XCTAssertEqual(archivedManifest?.supplementalItems.map(\.status), ["included", "included"])
        XCTAssertEqual(archivedManifest?.supplementalItems.map(\.sourcePathState), ["file", "file"])
        XCTAssertEqual(archivedManifest?.rotatedSupplementalSets.first?.sourcePathState, "directory")
        XCTAssertEqual(archivedManifest?.rotatedSupplementalSets.first?.copiedCount, 1)
        XCTAssertEqual(archivedManifest?.rotatedSupplementalSets.first?.status, "included")
    }

    func testExportManifestRecordsMissingSupplementalSourcePathState() async throws {
        let root = try temporaryDirectory()
        let productLogs = root.appendingPathComponent("product/logs", isDirectory: true)
        let missingSource = root.appendingPathComponent("missing-runtime-config.json")
        let destination = root.appendingPathComponent("export.zip")
        try FileManager.default.createDirectory(at: productLogs, withIntermediateDirectories: true)

        var archivedManifest: RuntimeLogExportManifest?
        let exporter = MacRuntimeControlLogExporter(
            logCollector: FakeRuntimeLogCollectorForExport(),
            productLogsDirectory: productLogs,
            supplementalLogItems: [
                RuntimeLogExportSupplementalSource(
                    source: missingSource,
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

        let item = try XCTUnwrap(archivedManifest?.supplementalItems.first)
        XCTAssertFalse(item.sourcePresent)
        XCTAssertFalse(item.included)
        XCTAssertEqual(item.sourcePathState, "missing")
        XCTAssertEqual(item.status, "missing")
        XCTAssertNil(item.error)
    }

    func testExportDoesNotOverwriteCentralLogsWithSupplementalSource() async throws {
        let root = try temporaryDirectory()
        let guestRun = root.appendingPathComponent("vm/data/run", isDirectory: true)
        let productLogs = root.appendingPathComponent("product/logs", isDirectory: true)
        let centralGuestLogs = productLogs.appendingPathComponent("guest", isDirectory: true)
        let destination = root.appendingPathComponent("export.zip")
        try FileManager.default.createDirectory(at: guestRun, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: centralGuestLogs, withIntermediateDirectories: true)
        try "source".write(
            to: guestRun.appendingPathComponent("bootstrap.log"),
            atomically: true,
            encoding: .utf8
        )
        try "central".write(
            to: centralGuestLogs.appendingPathComponent("bootstrap.log"),
            atomically: true,
            encoding: .utf8
        )

        var archivedBootstrapLog: String?
        let exporter = MacRuntimeControlLogExporter(
            logCollector: FakeRuntimeLogCollectorForExport(),
            productLogsDirectory: productLogs,
            supplementalLogItems: [
                RuntimeLogExportSupplementalSource(
                    source: guestRun.appendingPathComponent("bootstrap.log"),
                    relativeDestination: "guest/bootstrap.log"
                ),
            ],
            rotatedSupplementalSets: [],
            archiveRunner: { _, arguments in
                let bundleRoot = URL(fileURLWithPath: arguments[4])
                let temporaryArchive = URL(fileURLWithPath: arguments[5])
                archivedBootstrapLog = try? String(
                    contentsOf: bundleRoot.appendingPathComponent("guest/bootstrap.log")
                )
                try? "archive".write(to: temporaryArchive, atomically: true, encoding: .utf8)
                return RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
            }
        )

        _ = try await exporter.exportLogs(to: destination)

        XCTAssertEqual(archivedBootstrapLog, "central")
    }

    func testExportCanAddSupplementalLogsWhenCopiedCentralDirectoriesAreReadOnly() async throws {
        let root = try temporaryDirectory()
        let guestRun = root.appendingPathComponent("vm/data/run", isDirectory: true)
        let productLogs = root.appendingPathComponent("product/logs", isDirectory: true)
        let centralGuestLogs = productLogs.appendingPathComponent("guest", isDirectory: true)
        let destination = root.appendingPathComponent("export.zip")
        try FileManager.default.createDirectory(at: guestRun, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: centralGuestLogs, withIntermediateDirectories: true)
        try "source".write(
            to: guestRun.appendingPathComponent("container-logs.log"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: centralGuestLogs.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: centralGuestLogs.path)
        }

        var archivedContainerLog: String?
        let exporter = MacRuntimeControlLogExporter(
            logCollector: FakeRuntimeLogCollectorForExport(),
            productLogsDirectory: productLogs,
            supplementalLogItems: [
                RuntimeLogExportSupplementalSource(
                    source: guestRun.appendingPathComponent("container-logs.log"),
                    relativeDestination: "guest/container-logs.log"
                ),
            ],
            rotatedSupplementalSets: [],
            archiveRunner: { _, arguments in
                let bundleRoot = URL(fileURLWithPath: arguments[4])
                let temporaryArchive = URL(fileURLWithPath: arguments[5])
                archivedContainerLog = try? String(
                    contentsOf: bundleRoot.appendingPathComponent("guest/container-logs.log")
                )
                try? "archive".write(to: temporaryArchive, atomically: true, encoding: .utf8)
                return RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
            }
        )

        _ = try await exporter.exportLogs(to: destination)

        XCTAssertEqual(archivedContainerLog, "source")
    }

    func testExportContinuesWhenCollectionRefreshFails() async throws {
        let root = try temporaryDirectory()
        let productLogs = root.appendingPathComponent("product/logs", isDirectory: true)
        let destination = root.appendingPathComponent("export.zip")
        try FileManager.default.createDirectory(at: productLogs, withIntermediateDirectories: true)

        var archivedManifest: RuntimeLogExportManifest?
        let exporter = MacRuntimeControlLogExporter(
            logCollector: FailingRuntimeLogCollectorForExport(),
            productLogsDirectory: productLogs,
            supplementalLogItems: [],
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

        let result = try await exporter.exportLogs(to: destination)

        XCTAssertEqual(result.destination, destination)
        XCTAssertEqual(try String(contentsOf: destination), "archive")
        XCTAssertEqual(archivedManifest?.collectionIssue, "collection failed")
    }

    func testExportReplacesExistingDestinationArchive() async throws {
        let root = try temporaryDirectory()
        let productLogs = root.appendingPathComponent("product/logs", isDirectory: true)
        let destination = root.appendingPathComponent("export.zip")
        try FileManager.default.createDirectory(at: productLogs, withIntermediateDirectories: true)
        try "old archive".write(to: destination, atomically: true, encoding: .utf8)

        let exporter = MacRuntimeControlLogExporter(
            logCollector: FakeRuntimeLogCollectorForExport(),
            productLogsDirectory: productLogs,
            supplementalLogItems: [],
            rotatedSupplementalSets: [],
            archiveRunner: { _, arguments in
                let temporaryArchive = URL(fileURLWithPath: arguments[5])
                try? "new archive".write(to: temporaryArchive, atomically: true, encoding: .utf8)
                return RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
            }
        )

        let result = try await exporter.exportLogs(to: destination)

        XCTAssertEqual(result.destination, destination)
        XCTAssertEqual(try String(contentsOf: destination), "new archive")
    }

    func testExportFailsWhenDestinationArchivePathIsDirectory() async throws {
        let root = try temporaryDirectory()
        let productLogs = root.appendingPathComponent("product/logs", isDirectory: true)
        let destination = root.appendingPathComponent("export.zip", isDirectory: true)
        try FileManager.default.createDirectory(at: productLogs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let exporter = MacRuntimeControlLogExporter(
            logCollector: FakeRuntimeLogCollectorForExport(),
            productLogsDirectory: productLogs,
            supplementalLogItems: [],
            rotatedSupplementalSets: [],
            archiveRunner: { _, arguments in
                let temporaryArchive = URL(fileURLWithPath: arguments[5])
                try? "new archive".write(to: temporaryArchive, atomically: true, encoding: .utf8)
                return RuntimeCommandResult(exitCode: 0, stdout: "", stderr: "")
            }
        )

        do {
            _ = try await exporter.exportLogs(to: destination)
            XCTFail("Expected directory destination to fail")
        } catch let error as RuntimeLogExporterError {
            XCTAssertEqual(error, .unexpectedPathState(path: destination.path, state: "directory"))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    func testExportThrowsArchiveFailureWithCommandOutput() async throws {
        let root = try temporaryDirectory()
        let productLogs = root.appendingPathComponent("product/logs", isDirectory: true)
        let destination = root.appendingPathComponent("export.zip")
        try FileManager.default.createDirectory(at: productLogs, withIntermediateDirectories: true)

        let exporter = MacRuntimeControlLogExporter(
            logCollector: FakeRuntimeLogCollectorForExport(),
            productLogsDirectory: productLogs,
            supplementalLogItems: [],
            rotatedSupplementalSets: [],
            archiveRunner: { _, _ in
                RuntimeCommandResult(exitCode: 2, stdout: "stdout detail", stderr: "ditto denied")
            }
        )

        do {
            _ = try await exporter.exportLogs(to: destination)
            XCTFail("Expected log export failure")
        } catch {
            XCTAssertEqual(error.localizedDescription, "stdout detail\nditto denied")
        }
    }

    func testExportThrowsArchiveFailureWithFallbackSummary() async throws {
        let root = try temporaryDirectory()
        let productLogs = root.appendingPathComponent("product/logs", isDirectory: true)
        let destination = root.appendingPathComponent("export.zip")
        try FileManager.default.createDirectory(at: productLogs, withIntermediateDirectories: true)

        let exporter = MacRuntimeControlLogExporter(
            logCollector: FakeRuntimeLogCollectorForExport(),
            productLogsDirectory: productLogs,
            supplementalLogItems: [],
            rotatedSupplementalSets: [],
            archiveRunner: { _, _ in
                RuntimeCommandResult(exitCode: 7, stdout: "  ", stderr: "\n")
            }
        )

        do {
            _ = try await exporter.exportLogs(to: destination)
            XCTFail("Expected log export failure")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Command failed with exit code 7")
        }
    }

    func testExportThrowsArchiveFailureWithOutputIssueSummary() async throws {
        let root = try temporaryDirectory()
        let productLogs = root.appendingPathComponent("product/logs", isDirectory: true)
        let destination = root.appendingPathComponent("export.zip")
        try FileManager.default.createDirectory(at: productLogs, withIntermediateDirectories: true)

        let exporter = MacRuntimeControlLogExporter(
            logCollector: FakeRuntimeLogCollectorForExport(),
            productLogsDirectory: productLogs,
            supplementalLogItems: [],
            rotatedSupplementalSets: [],
            archiveRunner: { _, _ in
                RuntimeCommandResult(
                    exitCode: 7,
                    stdout: "",
                    stderr: "",
                    outputIssues: [
                        RuntimeCommandOutputIssue(
                            stream: .stderr,
                            message: "command stderr is not valid UTF-8"
                        ),
                    ]
                )
            }
        )

        do {
            _ = try await exporter.exportLogs(to: destination)
            XCTFail("Expected log export failure")
        } catch {
            XCTAssertEqual(error.localizedDescription, "stderr: command stderr is not valid UTF-8")
        }
    }

    func testExportSkipsUnreadableSupplementalSourceAndRecordsManifestIssue() async throws {
        let root = try temporaryDirectory()
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
            logCollector: FakeRuntimeLogCollectorForExport(),
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

        let item = try XCTUnwrap(archivedManifest?.supplementalItems.first)
        XCTAssertTrue(item.sourcePresent)
        XCTAssertFalse(item.included)
        XCTAssertEqual(item.status, "failed")
        XCTAssertNotNil(item.error)
    }

    func testExportContinuesWhenRotatedSupplementalSourceDirectoryIsUnexpectedPath() async throws {
        let root = try temporaryDirectory()
        let productLogs = root.appendingPathComponent("product/logs", isDirectory: true)
        let sourceDirectory = root.appendingPathComponent("runtime-events")
        let destination = root.appendingPathComponent("export.zip")
        try FileManager.default.createDirectory(at: productLogs, withIntermediateDirectories: true)
        try "not a directory".write(to: sourceDirectory, atomically: true, encoding: .utf8)

        var archivedManifest: RuntimeLogExportManifest?
        let exporter = MacRuntimeControlLogExporter(
            logCollector: FakeRuntimeLogCollectorForExport(),
            productLogsDirectory: productLogs,
            supplementalLogItems: [],
            rotatedSupplementalSets: [
                RuntimeLogExportRotatedSupplementalSet(
                    sourceDirectory: sourceDirectory,
                    sourceFilePrefix: "\(RuntimeDiagnosticsArtifactFileNames.runtimeEvents).",
                    relativeDestinationDirectory: "diagnostics/status",
                    destinationFilePrefix: "\(RuntimeDiagnosticsArtifactFileNames.runtimeEvents)."
                ),
            ],
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

        let result = try await exporter.exportLogs(to: destination)

        XCTAssertEqual(result.destination, destination)
        let item = try XCTUnwrap(archivedManifest?.rotatedSupplementalSets.first)
        XCTAssertEqual(item.sourcePathState, "file")
        XCTAssertEqual(item.copiedCount, 0)
        XCTAssertEqual(item.status, "failed")
        XCTAssertTrue(item.error?.contains("unexpected source path state: file") == true)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeLogExporterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private final class FakeRuntimeLogCollectorForExport: RuntimeLogCollecting, @unchecked Sendable {
    private(set) var refreshCount = 0

    func refreshLogCollection() throws {
        refreshCount += 1
    }
}

private struct FailingRuntimeLogCollectorForExport: RuntimeLogCollecting {
    func refreshLogCollection() throws {
        throw NSError(domain: "RuntimeLogExporterTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "collection failed",
        ])
    }
}

private final class FailingRemoveFileManager: FileManager, @unchecked Sendable {
    private let failingPath: String

    init(failingPath: String) {
        self.failingPath = failingPath
        super.init()
    }

    override func removeItem(at URL: URL) throws {
        if URL.path == failingPath {
            throw NSError(domain: "RuntimeLogExporterTests", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "cleanup denied",
            ])
        }
        try super.removeItem(at: URL)
    }
}
