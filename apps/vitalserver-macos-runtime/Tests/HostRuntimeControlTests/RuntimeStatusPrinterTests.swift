import Foundation
import RuntimeCore
import RuntimeContracts
@testable import HostRuntimeControl
import XCTest

final class RuntimeStatusPrinterTests: XCTestCase {
    func testPrintStatusUsesExplicitRuntimeStatusInputs() {
        var lines: [String] = []
        let executablePaths: Set<String> = [Constants.InstallPaths.vmBin]
        let existingFiles: Set<URL> = [
            URL(fileURLWithPath: "/runtime/status.json"),
            URL(fileURLWithPath: Constants.InstallPaths.vmBin),
            URL(fileURLWithPath: Constants.InstallPaths.proxyRun),
            URL(fileURLWithPath: "/runtime/rootfs.img.gz"),
        ]

        let printer = RuntimeStatusPrinter(
            productRoot: URL(fileURLWithPath: "/product"),
            runtimeDirectory: URL(fileURLWithPath: "/runtime"),
            runtimeStatus: URL(fileURLWithPath: "/runtime/status.json"),
            rootfsBase: URL(fileURLWithPath: "/runtime/rootfs.img.gz"),
            vmDisk: URL(fileURLWithPath: "/runtime/vm-disk.raw"),
            latestBackupPath: { "/runtime/backups/latest" },
            runtimeStatusValue: { "running" },
            runtimeVersionValue: { "2026.05.23" },
            vmIP: { "192.168.64.20" },
            installedProxyPort: { 18080 },
            hostProxyHTTP: { port in "200@\(port)" },
            isExecutableFile: { executablePaths.contains($0) },
            fileExists: { existingFiles.contains($0) },
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
            rootfsBase: URL(fileURLWithPath: "/runtime/rootfs.img.gz"),
            vmDisk: URL(fileURLWithPath: "/runtime/vm-disk.raw"),
            latestBackupPath: { nil },
            runtimeStatusValue: { "not-installed" },
            runtimeVersionValue: { "unknown" },
            vmIP: { "waiting" },
            installedProxyPort: { 8080 },
            hostProxyHTTP: { _ in "000" },
            isExecutableFile: { _ in false },
            fileExists: { _ in false },
            serviceState: { _ in .notLoaded },
            printLine: { lines.append($0) }
        )

        printer.printStatus()

        XCTAssertEqual(lines[3], "  latest backup: none")
    }
}
