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
            currentStatus: { RuntimeStatusPrinterCurrentStatus(status: .unknown("running"), vmIP: "192.168.64.20") },
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
            "  status diagnostics file: present",
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
            currentStatus: { RuntimeStatusPrinterCurrentStatus(status: .unknown("not-installed"), vmIP: "waiting") },
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
            currentStatus: { RuntimeStatusPrinterCurrentStatus(status: .unknown("not-installed"), vmIP: "waiting") },
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

    func testPrintStatusUsesCurrentStatusWhenStatusDocumentIsMissing() {
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
            currentStatus: { RuntimeStatusPrinterCurrentStatus(status: .healthy, vmIP: "192.168.64.30") },
            runtimeVersionValue: { "unknown" },
            installedProxyPort: { 8080 },
            hostProxyHTTP: { _ in "000" },
            fileStateAtPath: { _ in .missing },
            fileStateAtURL: { _ in .missing },
            serviceState: { _ in .notLoaded },
            printLine: { lines.append($0) }
        )

        printer.printStatus()

        XCTAssertEqual(lines[4], "  status diagnostics file: missing")
        XCTAssertEqual(lines[5], "  status: healthy")
        XCTAssertEqual(lines[14], "  VM IP: 192.168.64.30")
    }

    func testPrintStatusUsesCurrentStatusWhenStatusDocumentReadFails() {
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
            currentStatus: { RuntimeStatusPrinterCurrentStatus(status: .degraded, vmIP: nil) },
            runtimeVersionValue: { "unknown" },
            installedProxyPort: { 8080 },
            hostProxyHTTP: { _ in "000" },
            fileStateAtPath: { _ in .missing },
            fileStateAtURL: { _ in .missing },
            serviceState: { _ in .notLoaded },
            printLine: { lines.append($0) }
        )

        printer.printStatus()

        XCTAssertEqual(lines[4], "  status diagnostics file: missing")
        XCTAssertEqual(lines[5], "  status: degraded")
        XCTAssertEqual(lines[14], "  VM IP: not reported")
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
            currentStatus: { RuntimeStatusPrinterCurrentStatus(status: .degraded, vmIP: nil) },
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
}
