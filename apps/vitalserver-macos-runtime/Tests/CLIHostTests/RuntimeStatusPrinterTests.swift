import Foundation
import Bootstrap
import Application
import Contracts
import Domain
import InboundAdapters
@testable import CLIHost
import XCTest
import Errors

final class RuntimeStatusPrinterTests: XCTestCase {
    func testPrintStatusUsesExplicitRuntimeStatusInputs() {
        var lines: [String] = []
        let pathStates: [String: RuntimeFileState] = [
            Constants.InstallPaths.vmBin: .executable,
            Constants.InstallPaths.proxyRun: .present,
        ]
        let urlStates: [URL: RuntimeFileState] = [
            URL(fileURLWithPath: "/runtime/status.json"): .present,
            URL(fileURLWithPath: "/runtime/rootfs.img.gz"): .present,
        ]

        let printer = RuntimeStatusPrinter(
            productRoot: URL(fileURLWithPath: "/product"),
            runtimeDirectory: URL(fileURLWithPath: "/runtime"),
            runtimeStatus: URL(fileURLWithPath: "/runtime/status.json"),
            launcherPath: Constants.InstallPaths.vmBin,
            proxyRunnerPath: Constants.InstallPaths.proxyRun,
            rootfsBase: URL(fileURLWithPath: "/runtime/rootfs.img.gz"),
            vmDisk: URL(fileURLWithPath: "/runtime/vm-disk.raw"),
            latestBackupPath: { "/runtime/backups/latest" },
            runtimeStatusDocument: { .loaded(self.statusDocument(status: .unknown("running"), vmIP: "192.168.64.20")) },
            runtimeVersionValue: { "2026.05.23" },
            installedProxyPort: { 18080 },
            hostProxyHTTP: { port in "200@\(port)" },
            fileStateAtPath: { pathStates[$0] ?? .missing },
            fileStateAtURL: { urlStates[$0] ?? .missing },
            serviceState: { _ in .loaded },
            printLine: { lines.append($0) }
        )

        printer.printStatus()

        XCTAssertEqual(lines, [
            "Tirosh VitalServer runtime",
            "  product root: /product",
            "  runtime dir: /runtime",
            "  latest backup: /runtime/backups/latest",
            "  status file: present",
            "  status: running",
            "  launcher: executable",
            "  proxy runner: present",
            "  rootfs base: present",
            "  vm disk: missing",
            "  version: 2026.05.23",
            "  VM service: loaded",
            "  proxy service: loaded",
            "  watchdog service: loaded",
            "  VM IP: 192.168.64.20",
            "  proxy port: 18080",
            "  host proxy HTTP: 200@18080",
        ])
    }

    func testPrintStatusFallsBackWhenLatestBackupIsMissing() {
        var lines: [String] = []
        let printer = RuntimeStatusPrinter(
            productRoot: URL(fileURLWithPath: "/product"),
            runtimeDirectory: URL(fileURLWithPath: "/runtime"),
            runtimeStatus: URL(fileURLWithPath: "/runtime/status.json"),
            launcherPath: Constants.InstallPaths.vmBin,
            proxyRunnerPath: Constants.InstallPaths.proxyRun,
            rootfsBase: URL(fileURLWithPath: "/runtime/rootfs.img.gz"),
            vmDisk: URL(fileURLWithPath: "/runtime/vm-disk.raw"),
            latestBackupPath: { nil },
            runtimeStatusDocument: { .loaded(self.statusDocument(status: .unknown("not-installed"), vmIP: "waiting")) },
            runtimeVersionValue: { "unknown" },
            installedProxyPort: { 8080 },
            hostProxyHTTP: { _ in "000" },
            fileStateAtPath: { _ in .missing },
            fileStateAtURL: { _ in .missing },
            serviceState: { _ in .notLoaded },
            printLine: { lines.append($0) }
        )

        printer.printStatus()

        XCTAssertEqual(lines[3], "  latest backup: none")
    }

    func testPrintStatusReportsLatestBackupReadFailureDistinctFromMissing() {
        var lines: [String] = []
        let error = NSError(
            domain: "RuntimeStatusPrinterTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "backup directory inspection failed"]
        )
        let printer = RuntimeStatusPrinter(
            productRoot: URL(fileURLWithPath: "/product"),
            runtimeDirectory: URL(fileURLWithPath: "/runtime"),
            runtimeStatus: URL(fileURLWithPath: "/runtime/status.json"),
            launcherPath: Constants.InstallPaths.vmBin,
            proxyRunnerPath: Constants.InstallPaths.proxyRun,
            rootfsBase: URL(fileURLWithPath: "/runtime/rootfs.img.gz"),
            vmDisk: URL(fileURLWithPath: "/runtime/vm-disk.raw"),
            latestBackupPath: { throw error },
            runtimeStatusDocument: { .loaded(self.statusDocument(status: .unknown("not-installed"), vmIP: "waiting")) },
            runtimeVersionValue: { "unknown" },
            installedProxyPort: { 8080 },
            hostProxyHTTP: { _ in "000" },
            fileStateAtPath: { _ in .missing },
            fileStateAtURL: { _ in .missing },
            serviceState: { _ in .notLoaded },
            printLine: { lines.append($0) }
        )

        printer.printStatus()

        XCTAssertEqual(lines[3], "  latest backup: read failed: backup directory inspection failed")
    }

    func testPrintStatusReportsMissingStatusDocumentExplicitly() {
        var lines: [String] = []
        let printer = RuntimeStatusPrinter(
            productRoot: URL(fileURLWithPath: "/product"),
            runtimeDirectory: URL(fileURLWithPath: "/runtime"),
            runtimeStatus: URL(fileURLWithPath: "/runtime/status.json"),
            launcherPath: Constants.InstallPaths.vmBin,
            proxyRunnerPath: Constants.InstallPaths.proxyRun,
            rootfsBase: URL(fileURLWithPath: "/runtime/rootfs.img.gz"),
            vmDisk: URL(fileURLWithPath: "/runtime/vm-disk.raw"),
            latestBackupPath: { nil },
            runtimeStatusDocument: { .missing },
            runtimeVersionValue: { "unknown" },
            installedProxyPort: { 8080 },
            hostProxyHTTP: { _ in "000" },
            fileStateAtPath: { _ in .missing },
            fileStateAtURL: { _ in .missing },
            serviceState: { _ in .notLoaded },
            printLine: { lines.append($0) }
        )

        printer.printStatus()

        XCTAssertEqual(lines[5], "  status: missing status document")
        XCTAssertEqual(lines[14], "  VM IP: missing status document")
    }

    func testPrintStatusReportsStatusDocumentReadFailureDistinctFromMissing() {
        var lines: [String] = []
        let printer = RuntimeStatusPrinter(
            productRoot: URL(fileURLWithPath: "/product"),
            runtimeDirectory: URL(fileURLWithPath: "/runtime"),
            runtimeStatus: URL(fileURLWithPath: "/runtime/status.json"),
            launcherPath: Constants.InstallPaths.vmBin,
            proxyRunnerPath: Constants.InstallPaths.proxyRun,
            rootfsBase: URL(fileURLWithPath: "/runtime/rootfs.img.gz"),
            vmDisk: URL(fileURLWithPath: "/runtime/vm-disk.raw"),
            latestBackupPath: { nil },
            runtimeStatusDocument: { .failed("decode failed") },
            runtimeVersionValue: { "unknown" },
            installedProxyPort: { 8080 },
            hostProxyHTTP: { _ in "000" },
            fileStateAtPath: { _ in .missing },
            fileStateAtURL: { _ in .missing },
            serviceState: { _ in .notLoaded },
            printLine: { lines.append($0) }
        )

        printer.printStatus()

        XCTAssertEqual(lines[5], "  status: status document read failed: decode failed")
        XCTAssertEqual(lines[14], "  VM IP: status document read failed: decode failed")
    }

    func testPrintStatusPreservesFileInspectionFailure() {
        var lines: [String] = []
        let printer = RuntimeStatusPrinter(
            productRoot: URL(fileURLWithPath: "/product"),
            runtimeDirectory: URL(fileURLWithPath: "/runtime"),
            runtimeStatus: URL(fileURLWithPath: "/runtime/status.json"),
            launcherPath: Constants.InstallPaths.vmBin,
            proxyRunnerPath: Constants.InstallPaths.proxyRun,
            rootfsBase: URL(fileURLWithPath: "/runtime/rootfs.img.gz"),
            vmDisk: URL(fileURLWithPath: "/runtime/vm-disk.raw"),
            latestBackupPath: { nil },
            runtimeStatusDocument: { .missing },
            runtimeVersionValue: { "unknown" },
            installedProxyPort: { nil },
            hostProxyHTTP: { _ in "000" },
            fileStateAtPath: { path in
                path == Constants.InstallPaths.vmBin ? .inspectFailed("permission denied") : .missing
            },
            fileStateAtURL: { url in
                url.path == "/runtime/rootfs.img.gz" ? .inspectFailed("stat failed") : .missing
            },
            serviceState: { _ in .notLoaded },
            printLine: { lines.append($0) }
        )

        printer.printStatus()

        XCTAssertEqual(lines[6], "  launcher: inspect-failed: permission denied")
        XCTAssertEqual(lines[8], "  rootfs base: inspect-failed: stat failed")
    }

    private func statusDocument(status: RuntimeStatusLevel, vmIP: String?) -> RuntimeStatusDocument {
        RuntimeStatusDocument(
            product: "VitalServerHelper",
            status: status,
            operation: .health,
            message: "runtime status",
            updatedAt: "2026-05-22T00:00:00Z",
            productRoot: "/product",
            runtimeHome: "/runtime",
            runtimeVersion: "2026.05.23",
            vmService: .loaded,
            proxyService: .loaded,
            watchdogService: .loaded,
            vmIP: vmIP,
            proxyPort: 18080,
            hostProxyHTTP: "200",
            guestHTTP: "200",
            redisUIHTTP: nil,
            swaggerUIHTTP: nil,
            rootfsBase: .present,
            vmDisk: .present,
            failureReasons: [],
            latestBackup: nil
        )
    }
}
