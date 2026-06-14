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
            "--restart",
        ])

        XCTAssertEqual(command, .configure(RuntimeConfigureCommand(
            changes: [
                .cpu(8),
                .network(.bridged),
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
