import Foundation
import Application
import InboundAdapters
@testable import CLIHost
import XCTest
import Errors

final class RuntimeLifecycleCommandTests: XCTestCase {
    func testParsesCommandsWithoutArguments() throws {
        XCTAssertEqual(try RuntimeLifecycleCommand.parse([]), .help)
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["install"]), .install)
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["install-provision"]), .installProvision)
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["preinstall-check"]), .preinstallCheck)
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["status"]), .status)
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["health"]), .health)
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["guest-log-sync"]), .guestLogSync)
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["watchdog"]), .watchdog)
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["redis-backup"]), .redisBackup)
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["repair-datastore"]), .repairDatastore)
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["repair-vm-disk"]), .repairVMDisk)
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["repair-services"]), .repairServices)
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["start-services"]), .startServices)
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["stop-services"]), .stopServices)
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["uninstall"]), .uninstall(RuntimeUninstallCommand(clean: false)))
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["--help"]), .help)
    }

    func testParsesCleanUninstallCommand() throws {
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse(["uninstall", "--clean"]),
            .uninstall(RuntimeUninstallCommand(clean: true))
        )
    }

    func testParsesConfigureArgumentsIntoTypedCommand() throws {
        let command = try RuntimeLifecycleCommand.parse([
            "configure",
            "--cpu",
            "8",
            "--network",
            "shared",
            "--start-on-boot",
            "false",
            "--restart",
        ])

        XCTAssertEqual(command, .configure(RuntimeConfigureCommand(
            changes: [
                .cpu(8),
                .network(.shared),
                .startOnBoot(false),
            ],
            restart: true
        )))
    }

    func testParsesBundleCommands() throws {
        let bundleURL = URL(fileURLWithPath: "/tmp/update-bundle.tar.gz")

        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse(["verify-bundle", bundleURL.path]),
            .verifyBundle(bundleURL)
        )
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse(["stage-bundle", bundleURL.path]),
            .stageBundle(bundleURL)
        )
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse(["apply-bundle", bundleURL.path]),
            .applyBundle(bundleURL)
        )
    }

    func testParsesOptionalRollbackPath() throws {
        XCTAssertEqual(try RuntimeLifecycleCommand.parse(["rollback"]), .rollback(.latestBackup))
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parse(["rollback", "/backups/latest"]),
            .rollback(.specificBackup(URL(fileURLWithPath: "/backups/latest")))
        )
    }

    func testBundleCommandsRequirePath() {
        assertMissingArgument(
            try RuntimeLifecycleCommand.parse(["verify-bundle"]),
            expectedMessage: "usage: vitalserver-vm runtime verify-bundle <bundle.tar.gz>"
        )
        assertMissingArgument(
            try RuntimeLifecycleCommand.parse(["stage-bundle"]),
            expectedMessage: "usage: vitalserver-vm runtime stage-bundle <bundle.tar.gz>"
        )
        assertMissingArgument(
            try RuntimeLifecycleCommand.parse(["apply-bundle"]),
            expectedMessage: "usage: vitalserver-vm runtime apply-bundle <bundle.tar.gz>"
        )
    }

    func testConfigureRejectsMissingValueAndInvalidClosedChoice() {
        assertMissingArgument(
            try RuntimeLifecycleCommand.parse(["configure", "--cpu"]),
            expectedMessage: "missing value for --cpu"
        )
        assertMissingArgument(
            try RuntimeLifecycleCommand.parse(["configure", "--network", "host"]),
            expectedMessage: "--network must be `shared` or `bridged`"
        )
        assertMissingArgument(
            try RuntimeLifecycleCommand.parse(["configure", "--start-on-boot", "sometimes"]),
            expectedMessage: "--start-on-boot must be true or false"
        )
    }

    func testUnsupportedCommandIncludesRuntimePrefix() {
        XCTAssertThrowsError(try RuntimeLifecycleCommand.parse(["unknown"])) { error in
            XCTAssertEqual(
                String(describing: error),
                String(describing: LauncherError.unsupportedCommand("runtime unknown"))
            )
        }
    }

    func testUsageListsRuntimeCommands() {
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime install"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime install-provision"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime preinstall-check"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime apply-bundle <bundle.tar.gz>"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime redis-backup"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime repair-vm-disk"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime repair-services"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime stop-services"))
        XCTAssertTrue(RuntimeLifecycleCommand.usage.contains("vitalserver-vm runtime uninstall [--clean]"))
    }

    private func assertMissingArgument(
        _ expression: @autoclosure () throws -> RuntimeLifecycleCommand,
        expectedMessage: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(
                String(describing: error),
                String(describing: LauncherError.missingArgument(expectedMessage)),
                file: file,
                line: line
            )
        }
    }
}
