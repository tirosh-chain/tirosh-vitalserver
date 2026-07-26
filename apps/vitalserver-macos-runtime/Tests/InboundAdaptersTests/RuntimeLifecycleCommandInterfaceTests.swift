import Foundation
import Application
import InboundAdapters
import XCTest
import Errors

final class RuntimeLifecycleCommandInterfaceTests: XCTestCase {
    func testParsesRuntimeArgumentsIntoTypedInterfaceCommand() throws {
        let command = try RuntimeLifecycleCommand.parseArguments([
            "configure",
            "--cpu",
            "8",
            "--network",
            "bridged",
            "--runtime-control-port",
            "18444",
            "--restart",
        ])

        XCTAssertEqual(command, .configure(RuntimeConfigureCommand(
            changes: [
                .cpu(8),
                .network(.bridged),
                .runtimeControlPort(18444),
            ],
            restart: true
        )))
    }

    func testReportsTypedParseErrorsWithoutCLIHostErrorDependency() {
        XCTAssertThrowsError(try RuntimeLifecycleCommand.parseArguments(["configure", "--cpu"])) { error in
            XCTAssertEqual(
                error as? RuntimeLifecycleCommandParseError,
                .missingArgument("missing value for --cpu")
            )
        }

        XCTAssertThrowsError(try RuntimeLifecycleCommand.parseArguments(["unknown"])) { error in
            XCTAssertEqual(
                error as? RuntimeLifecycleCommandParseError,
                .unsupportedCommand("runtime unknown")
            )
        }
    }

    func testParsesExplicitVMRuntimeRestartIntent() throws {
        let command = try RuntimeLifecycleCommand.parseArguments([
            "configure",
            "--restart-vm-runtime",
        ])

        XCTAssertEqual(command, .configure(RuntimeConfigureCommand(
            activation: .restartVMRuntime
        )))
    }

    func testRejectsConflictingActivationIntents() {
        XCTAssertThrowsError(try RuntimeLifecycleCommand.parseArguments([
            "configure",
            "--restart",
            "--restart-vm-runtime",
        ])) { error in
            XCTAssertEqual(
                error as? RuntimeLifecycleCommandParseError,
                .missingArgument("--restart and --restart-vm-runtime are mutually exclusive")
            )
        }
    }

    func testParsesRuntimeDataBackupCommand() throws {
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parseArguments(["runtime-data-backup"]),
            .runtimeDataBackup
        )
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parseArguments(["automatic-backup"]),
            .automaticBackup
        )
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parseArguments(["runtime-data-restore", "/backups/vitalserver-helper/manual"]),
            .runtimeDataRestore(URL(fileURLWithPath: "/backups/vitalserver-helper/manual"))
        )
        XCTAssertEqual(
            try RuntimeLifecycleCommand.parseArguments(["redis-restore", "/backups/redis/redis.tar.gz"]),
            .redisRestore(URL(fileURLWithPath: "/backups/redis/redis.tar.gz"))
        )
    }

    func testUsageTextListsRuntimeCommandsAtInterfaceBoundary() {
        XCTAssertTrue(RuntimeLifecycleCommand.usageText.contains("vitalserver-vm runtime install"))
        XCTAssertTrue(RuntimeLifecycleCommand.usageText.contains("vitalserver-vm runtime configure"))
        XCTAssertTrue(RuntimeLifecycleCommand.usageText.contains("vitalserver-vm runtime runtime-data-backup"))
        XCTAssertTrue(RuntimeLifecycleCommand.usageText.contains("vitalserver-vm runtime automatic-backup"))
        XCTAssertTrue(RuntimeLifecycleCommand.usageText.contains("vitalserver-vm runtime runtime-data-restore"))
        XCTAssertTrue(
            RuntimeLifecycleCommand.usageText.contains(
                "vitalserver-vm runtime uninstall [--clean|--force-clean|--force-clean-uninstaller]"
            )
        )
    }
}
