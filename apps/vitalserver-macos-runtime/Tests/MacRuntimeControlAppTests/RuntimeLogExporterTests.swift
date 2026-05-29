import Foundation
import Contracts
import RuntimeControl
@testable import MacHostRuntimeAdapter
@testable import MacRuntimeControlApp
import XCTest

@MainActor
final class RuntimeLogExporterTests: XCTestCase {
    func testDefaultExportFallbacksIncludeDiagnosticStateFiles() {
        let destinations = Set(RuntimeLogExportFallback.defaultItems().map(\.relativeDestination))

        XCTAssertTrue(destinations.contains("diagnostics/status/\(RuntimeFileNames.runtimeStatus)"))
        XCTAssertTrue(destinations.contains("diagnostics/status/\(RuntimeFileNames.runtimeEvents)"))
        XCTAssertTrue(destinations.contains("diagnostics/status/\(RuntimeFileNames.runtimeObservabilityDB)"))
        XCTAssertTrue(destinations.contains("diagnostics/status/\(RuntimeFileNames.runtimeObservabilityDB)-wal"))
        XCTAssertTrue(destinations.contains("diagnostics/status/\(RuntimeFileNames.runtimeObservabilityDB)-shm"))
        XCTAssertTrue(destinations.contains("diagnostics/guest/\(RuntimeFileNames.runtimeState)"))
        XCTAssertTrue(destinations.contains("diagnostics/guest/\(RuntimeFileNames.vmIP)"))
        XCTAssertTrue(destinations.contains("diagnostics/runtime/vm-config.json"))
        XCTAssertTrue(destinations.contains("diagnostics/runtime/runtime-version.json"))
        XCTAssertTrue(destinations.contains("diagnostics/guest/runtime-config.json"))
        XCTAssertTrue(destinations.contains("diagnostics/host/com.tirosh.vitalserver-proxy.plist"))
        XCTAssertTrue(destinations.contains("diagnostics/host/vitalserver-nginx.conf"))
    }

    func testDefaultRotatedExportFallbacksIncludeRuntimeEventHistory() {
        let runtimeEventSet = RuntimeLogExportRotatedFallbackSet.defaultSets().first {
            $0.sourceFilePrefix == "\(RuntimeFileNames.runtimeEvents)."
        }

        XCTAssertEqual(runtimeEventSet?.relativeDestinationDirectory, "diagnostics/status")
        XCTAssertEqual(runtimeEventSet?.destinationFilePrefix, "\(RuntimeFileNames.runtimeEvents).")
    }

    func testExportRefreshesCollectionAndIncludesFallbackGuestLogs() async throws {
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
        let exporter = MacHostRuntimeLogExporter(
            logCollector: collector,
            productLogsDirectory: productLogs,
            fallbackLogItems: [
                RuntimeLogExportFallback(
                    source: guestRun.appendingPathComponent("bootstrap.log"),
                    relativeDestination: "guest/bootstrap.log"
                ),
                RuntimeLogExportFallback(
                    source: guestRun.appendingPathComponent("container-logs.log"),
                    relativeDestination: "guest/container-logs.log"
                ),
            ],
            rotatedFallbackSets: [
                RuntimeLogExportRotatedFallbackSet(
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
        XCTAssertEqual(archivedManifest?.fallbackItems.count, 2)
        XCTAssertEqual(archivedManifest?.fallbackItems.map(\.included), [true, true])
    }

    func testExportDoesNotOverwriteCentralLogsWithFallbackSource() async throws {
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
        let exporter = MacHostRuntimeLogExporter(
            logCollector: FakeRuntimeLogCollectorForExport(),
            productLogsDirectory: productLogs,
            fallbackLogItems: [
                RuntimeLogExportFallback(
                    source: guestRun.appendingPathComponent("bootstrap.log"),
                    relativeDestination: "guest/bootstrap.log"
                ),
            ],
            rotatedFallbackSets: [],
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

    func testExportCanAddFallbackLogsWhenCopiedCentralDirectoriesAreReadOnly() async throws {
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
        let exporter = MacHostRuntimeLogExporter(
            logCollector: FakeRuntimeLogCollectorForExport(),
            productLogsDirectory: productLogs,
            fallbackLogItems: [
                RuntimeLogExportFallback(
                    source: guestRun.appendingPathComponent("container-logs.log"),
                    relativeDestination: "guest/container-logs.log"
                ),
            ],
            rotatedFallbackSets: [],
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

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeLogExporterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private final class FakeRuntimeLogCollectorForExport: RuntimeLogCollecting, @unchecked Sendable {
    private(set) var refreshCount = 0

    func refreshLogCollection() {
        refreshCount += 1
    }
}
